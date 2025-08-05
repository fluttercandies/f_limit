import 'dart:async';
import 'dart:collection';

/// A function that takes arguments and returns a Future
typedef LimitedFunction<T> = Future<T> Function();

/// Queue strategy for task execution
enum QueueStrategy {
  /// First In, First Out (default)
  fifo,

  /// Last In, First Out (stack-like behavior)
  lifo,

  /// Priority-based execution
  priority,
}

/// Options for creating a limited function
class LimitOptions {
  final int concurrency;
  final QueueStrategy queueStrategy;

  const LimitOptions({
    required this.concurrency,
    this.queueStrategy = QueueStrategy.fifo,
  });
}

/// Task wrapper with priority support
class _TaskWrapper {
  final Completer<void> completer;
  final int priority;
  final DateTime createdAt;

  _TaskWrapper({
    required this.completer,
    this.priority = 0,
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();
}

/// Abstract queue implementation
abstract class _TaskQueue {
  int get length;
  bool get isEmpty;
  bool get isNotEmpty;

  void add(_TaskWrapper task);
  _TaskWrapper removeNext();
  void clear();
}

/// FIFO queue implementation
class _FifoQueue implements _TaskQueue {
  final Queue<_TaskWrapper> _queue = Queue<_TaskWrapper>();

  @override
  int get length => _queue.length;

  @override
  bool get isEmpty => _queue.isEmpty;

  @override
  bool get isNotEmpty => _queue.isNotEmpty;

  @override
  void add(_TaskWrapper task) {
    _queue.add(task);
  }

  @override
  _TaskWrapper removeNext() {
    return _queue.removeFirst();
  }

  @override
  void clear() {
    _queue.clear();
  }
}

/// LIFO queue implementation (stack-like)
class _LifoQueue implements _TaskQueue {
  final Queue<_TaskWrapper> _queue = Queue<_TaskWrapper>();

  @override
  int get length => _queue.length;

  @override
  bool get isEmpty => _queue.isEmpty;

  @override
  bool get isNotEmpty => _queue.isNotEmpty;

  @override
  void add(_TaskWrapper task) {
    _queue.add(task);
  }

  @override
  _TaskWrapper removeNext() {
    return _queue.removeLast();
  }

  @override
  void clear() {
    _queue.clear();
  }
}

/// Priority queue implementation
class _PriorityQueue implements _TaskQueue {
  final List<_TaskWrapper> _heap = [];

  @override
  int get length => _heap.length;

  @override
  bool get isEmpty => _heap.isEmpty;

  @override
  bool get isNotEmpty => _heap.isNotEmpty;

  @override
  void add(_TaskWrapper task) {
    _heap.add(task);
    _bubbleUp(_heap.length - 1);
  }

  @override
  _TaskWrapper removeNext() {
    if (_heap.isEmpty) {
      throw StateError('Queue is empty');
    }

    final result = _heap.first;
    final last = _heap.removeLast();

    if (_heap.isNotEmpty) {
      _heap[0] = last;
      _bubbleDown(0);
    }

    return result;
  }

  @override
  void clear() {
    _heap.clear();
  }

  void _bubbleUp(int index) {
    if (index == 0) return;

    final parentIndex = (index - 1) ~/ 2;
    final current = _heap[index];
    final parent = _heap[parentIndex];

    // Higher priority (larger number) or same priority but earlier creation time
    if (_shouldSwap(current, parent)) {
      _heap[index] = parent;
      _heap[parentIndex] = current;
      _bubbleUp(parentIndex);
    }
  }

  void _bubbleDown(int index) {
    final leftChild = 2 * index + 1;
    final rightChild = 2 * index + 2;
    int largest = index;

    if (leftChild < _heap.length &&
        _shouldSwap(_heap[leftChild], _heap[largest])) {
      largest = leftChild;
    }

    if (rightChild < _heap.length &&
        _shouldSwap(_heap[rightChild], _heap[largest])) {
      largest = rightChild;
    }

    if (largest != index) {
      final temp = _heap[index];
      _heap[index] = _heap[largest];
      _heap[largest] = temp;
      _bubbleDown(largest);
    }
  }

  bool _shouldSwap(_TaskWrapper a, _TaskWrapper b) {
    // Higher priority first
    if (a.priority != b.priority) {
      return a.priority > b.priority;
    }
    // Same priority, earlier creation time first (FIFO for same priority)
    return a.createdAt.isBefore(b.createdAt);
  }
}

/// A concurrency limiter that controls how many async operations can run simultaneously
class FLimit {
  int _concurrency;
  final _TaskQueue _queue;
  final QueueStrategy _queueStrategy;
  int _activeCount = 0;

  FLimit(int concurrency, {QueueStrategy queueStrategy = QueueStrategy.fifo})
      : _concurrency = concurrency,
        _queueStrategy = queueStrategy,
        _queue = _createQueue(queueStrategy) {
    _validateConcurrency(concurrency);
  }

  static _TaskQueue _createQueue(QueueStrategy strategy) {
    switch (strategy) {
      case QueueStrategy.fifo:
        return _FifoQueue();
      case QueueStrategy.lifo:
        return _LifoQueue();
      case QueueStrategy.priority:
        return _PriorityQueue();
    }
  }

  /// Current number of active operations
  int get activeCount => _activeCount;

  /// Current number of pending operations in the queue
  int get pendingCount => _queue.length;

  /// Current concurrency limit
  int get concurrency => _concurrency;

  /// Current queue strategy
  QueueStrategy get queueStrategy => _queueStrategy;

  /// Set new concurrency limit
  set concurrency(int newConcurrency) {
    _validateConcurrency(newConcurrency);
    _concurrency = newConcurrency;

    // Use scheduleMicrotask to ensure this runs in the next microtask
    scheduleMicrotask(() {
      while (_activeCount < _concurrency && _queue.isNotEmpty) {
        _resumeNext();
      }
    });
  }

  /// Clear all pending operations from the queue
  void clearQueue() {
    _queue.clear();
  }

  /// Execute a function with concurrency limit
  Future<T> call<T>(Future<T> Function() function, {int priority = 0}) {
    final completer = Completer<T>();

    _enqueue(() async {
      try {
        final result = await function();
        completer.complete(result);
      } catch (error, stackTrace) {
        completer.completeError(error, stackTrace);
      }
    }, priority: priority);

    return completer.future;
  }

  void _enqueue(Future<void> Function() function, {int priority = 0}) {
    final internalCompleter = Completer<void>();
    final taskWrapper = _TaskWrapper(
      completer: internalCompleter,
      priority: priority,
    );

    _queue.add(taskWrapper);

    internalCompleter.future.then((_) async {
      await _run(function);
    });

    // Check if we can start processing immediately
    scheduleMicrotask(() {
      if (_activeCount < _concurrency && _queue.isNotEmpty) {
        _resumeNext();
      }
    });
  }

  Future<void> _run(Future<void> Function() function) async {
    try {
      await function();
    } catch (_) {
      // Errors are handled by the completer in the call method
    } finally {
      _next();
    }
  }

  void _resumeNext() {
    if (_activeCount < _concurrency && _queue.isNotEmpty) {
      final taskWrapper = _queue.removeNext();
      _activeCount++;
      taskWrapper.completer.complete();
    }
  }

  void _next() {
    _activeCount--;
    _resumeNext();
  }

  void _validateConcurrency(int concurrency) {
    if (concurrency <= 0 || !concurrency.isFinite) {
      throw ArgumentError('Expected concurrency to be a number from 1 and up');
    }
  }
}

/// Create a function with limited concurrency
typedef LimitedFunctionWrapper<T> = Future<T> Function();

/// Create a limited version of a function
LimitedFunctionWrapper<T> limitFunction<T>(
  Future<T> Function() function,
  LimitOptions options,
) {
  final limit =
      FLimit(options.concurrency, queueStrategy: options.queueStrategy);
  return () => limit(function);
}

/// Create a concurrency limiter
FLimit fLimit(int concurrency,
    {QueueStrategy queueStrategy = QueueStrategy.fifo}) {
  return FLimit(concurrency, queueStrategy: queueStrategy);
}
