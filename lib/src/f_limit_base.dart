import 'dart:async';
import 'dart:collection';
import 'dart:math';

/// A function that takes no arguments and returns a Future
typedef LimitedFunction<T> = Future<T> Function();

/// Queue strategy for task execution
///
/// Determines the order in which queued tasks are executed when concurrency
/// slots become available.
///
/// Example:
/// ```dart
/// // Use priority-based execution
/// final limit = fLimit(2, queueStrategy: QueueStrategy.priority);
///
/// limit(() async => print('low'), priority: 1);
/// limit(() async => print('high'), priority: 10);
/// // Output: high, low
/// ```
enum QueueStrategy {
  /// First In, First Out (default)
  ///
  /// Tasks are executed in the order they were added to the queue.
  /// This provides fair execution for all tasks.
  fifo,

  /// Last In, First Out (stack-like behavior)
  ///
  /// The most recently added task executes first. Useful for
  /// cache-like scenarios where newer data is more important.
  lifo,

  /// Priority-based execution
  ///
  /// Tasks with higher priority values execute first. When priorities
  /// are equal, tasks execute in FIFO order.
  priority,

  /// Alternating between head and tail
  ///
  /// Alternates between taking tasks from the front and back of the queue.
  /// Provides fair scheduling for both ends of the queue.
  ///
  /// Example:
  /// ```dart
  /// final limit = fLimit(1, queueStrategy: QueueStrategy.alternating);
  /// for (int i = 0; i < 5; i++) {
  ///   limit(() async => print(i));
  /// }
  /// // Output order: 0, 4, 1, 3, 2
  /// ```
  alternating,

  /// Random selection from queue
  ///
  /// Selects a random task from the queue each time a slot becomes available.
  /// Useful for load balancing and fair distribution across all queued tasks.
  ///
  /// Example:
  /// ```dart
  /// final limit = fLimit(1, queueStrategy: QueueStrategy.random);
  /// for (int i = 0; i < 5; i++) {
  ///   limit(() async => print(i));
  /// }
  /// // Output order: random (e.g., 3, 1, 4, 0, 2)
  /// ```
  random,
}

/// Options for creating a limited function
///
/// Used with [limitFunction] to configure concurrency limits and queue strategy.
///
/// Example:
/// ```dart
/// final options = LimitOptions(
///   concurrency: 2,
///   queueStrategy: QueueStrategy.priority,
/// );
/// final limited = limitFunction(myFunction, options);
/// ```
class LimitOptions {
  /// Maximum number of concurrent operations
  final int concurrency;

  /// Queue execution strategy
  final QueueStrategy queueStrategy;

  /// Creates options for limiting function concurrency
  ///
  /// [concurrency] must be >= 1
  /// [queueStrategy] defaults to [QueueStrategy.fifo]
  const LimitOptions({
    required this.concurrency,
    this.queueStrategy = QueueStrategy.fifo,
  });
}

/// Task wrapper with priority support
///
/// Internal class used to wrap queued tasks with metadata.
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
///
/// Internal interface for different queue strategies.
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

/// Alternating queue implementation (head, tail, head, tail, ...)
class _AlternatingQueue implements _TaskQueue {
  final Queue<_TaskWrapper> _queue = Queue<_TaskWrapper>();
  bool _takeFromHead = true;

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
    final task = _takeFromHead ? _queue.removeFirst() : _queue.removeLast();
    _takeFromHead = !_takeFromHead;
    return task;
  }

  @override
  void clear() {
    _queue.clear();
  }
}

/// Random queue implementation (random selection from any position)
class _RandomQueue implements _TaskQueue {
  final List<_TaskWrapper> _list = [];
  final Random _random = Random();

  @override
  int get length => _list.length;

  @override
  bool get isEmpty => _list.isEmpty;

  @override
  bool get isNotEmpty => _list.isNotEmpty;

  @override
  void add(_TaskWrapper task) {
    _list.add(task);
  }

  @override
  _TaskWrapper removeNext() {
    if (_list.isEmpty) {
      throw StateError('Queue is empty');
    }
    final index = _random.nextInt(_list.length);
    return _list.removeAt(index);
  }

  @override
  void clear() {
    _list.clear();
  }
}

/// A concurrency limiter that controls how many async operations can run simultaneously
///
/// Example:
/// ```dart
/// final limit = fLimit(2); // Max 2 concurrent operations
///
/// // Execute with limit
/// final result = await limit(() async {
///   return fetchData();
/// });
///
/// // With priority (when using priority strategy)
/// final limit = fLimit(1, queueStrategy: QueueStrategy.priority);
/// limit(() async => print('low'), priority: 1);
/// limit(() async => print('high'), priority: 10);
/// ```
class FLimit {
  int _concurrency;
  final _TaskQueue _queue;
  final QueueStrategy _queueStrategy;
  int _activeCount = 0;

  /// Creates a concurrency limiter
  ///
  /// [concurrency] must be >= 1 and determines the maximum number of
  /// concurrent operations.
  ///
  /// [queueStrategy] determines how queued tasks are executed when slots
  /// become available. Defaults to [QueueStrategy.fifo].
  ///
  /// Throws [ArgumentError] if concurrency is less than 1 or infinite.
  ///
  /// Example:
  /// ```dart
  /// final limit = FLimit(2, queueStrategy: QueueStrategy.priority);
  /// ```
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
      case QueueStrategy.alternating:
        return _AlternatingQueue();
      case QueueStrategy.random:
        return _RandomQueue();
    }
  }

  /// Current number of active operations
  ///
  /// Returns the number of operations currently being executed.
  int get activeCount => _activeCount;

  /// Current number of pending operations in the queue
  ///
  /// Returns the number of operations waiting for a slot to become available.
  int get pendingCount => _queue.length;

  /// Current concurrency limit
  ///
  /// Can be changed at runtime to increase or decrease the limit.
  ///
  /// Example:
  /// ```dart
  /// final limit = fLimit(2);
  /// limit.concurrency = 5; // Increase to 5
  /// ```
  int get concurrency => _concurrency;

  /// Current queue strategy
  ///
  /// Returns the strategy that was set when creating the limiter.
  QueueStrategy get queueStrategy => _queueStrategy;

  /// Set new concurrency limit
  ///
  /// Can be changed at runtime. Increasing the limit will immediately
  /// start processing queued tasks if slots are available.
  ///
  /// Throws [ArgumentError] if value is less than 1 or infinite.
  ///
  /// Example:
  /// ```dart
  /// final limit = fLimit(1);
  /// limit.concurrency = 10; // Scale up
  /// ```
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
  ///
  /// Removes all queued tasks without executing them. Active operations
  /// are not affected.
  ///
  /// Example:
  /// ```dart
  /// final limit = fLimit(1);
  /// // Add 100 tasks...
  /// limit.clearQueue(); // Cancel all pending
  /// print(limit.pendingCount); // 0
  /// ```
  void clearQueue() {
    _queue.clear();
  }

  /// Execute a function with concurrency limit
  ///
  /// If the concurrency limit has not been reached, the function executes
  /// immediately. Otherwise, it is queued according to the [queueStrategy].
  ///
  /// [priority] is used when [queueStrategy] is [QueueStrategy.priority].
  /// Higher values execute first. Defaults to 0.
  ///
  /// Returns a Future that completes with the result of [function].
  ///
  /// Example:
  /// ```dart
  /// final result = await limit(() async {
  ///   return fetchData();
  /// });
  ///
  /// // With priority
  /// await limit(() async => criticalTask(), priority: 10);
  /// ```
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
///
/// Returns a wrapped version of [function] that respects the concurrency
/// limits specified in [options].
///
/// Example:
/// ```dart
/// Future<String> fetchData() async {
///   return await http.get('https://api.example.com');
/// }
///
/// final limitedFetch = limitFunction(
///   fetchData,
///   LimitOptions(concurrency: 5),
/// );
///
/// // All calls respect the 5-concurrent limit
/// final results = await Future.wait([
///   limitedFetch(),
///   limitedFetch(),
///   limitedFetch(),
/// ]);
/// ```
LimitedFunctionWrapper<T> limitFunction<T>(
  Future<T> Function() function,
  LimitOptions options,
) {
  final limit =
      FLimit(options.concurrency, queueStrategy: options.queueStrategy);
  return () => limit(function);
}

/// Create a concurrency limiter
///
/// Convenience function that creates an [FLimit] instance.
///
/// [concurrency] must be >= 1.
/// [queueStrategy] determines task execution order. Defaults to [QueueStrategy.fifo].
///
/// Example:
/// ```dart
/// final limit = fLimit(2);
///
/// await limit(() async {
///   print('Running with concurrency limit');
/// });
///
/// // With custom strategy
/// final priority = fLimit(1, queueStrategy: QueueStrategy.priority);
/// priority(() async => taskA(), priority: 10);
/// priority(() async => taskB(), priority: 1);
/// // taskA runs first
/// ```
FLimit fLimit(int concurrency,
    {QueueStrategy queueStrategy = QueueStrategy.fifo}) {
  return FLimit(concurrency, queueStrategy: queueStrategy);
}
