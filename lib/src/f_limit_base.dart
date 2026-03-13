import 'dart:async';
import 'dart:collection';
import 'dart:math';

import 'retry.dart';

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

Duration? _validateOptionalDuration(Duration? value, String name) {
  if (value != null && value.isNegative) {
    throw ArgumentError.value(value, name, 'Must not be negative.');
  }
  return value;
}

/// Execution state for a submitted task.
enum TaskStatus {
  /// The task is waiting in the queue.
  pending,

  /// The task has started running.
  running,

  /// The task completed successfully.
  completed,

  /// The task completed with an error.
  ///
  /// This can happen either after execution starts, or before execution begins
  /// when queue/total timeout rules fail the task while it is still pending.
  failed,

  /// The task was canceled before it completed.
  canceled,
}

/// Timeout phases supported by [TaskTimeouts].
enum TimeoutStage {
  /// Timeout while waiting in the queue.
  queue,

  /// Timeout while running after execution started.
  run,

  /// Timeout measured from submission until completion.
  total,
}

/// Timeout configuration for a task.
///
/// [queue] fails the task if it waits in the queue too long.
/// [run] fails the task if execution takes too long after it starts.
/// [total] fails the task if the whole lifecycle from submission to completion
/// exceeds the duration.
class TaskTimeouts {
  final Duration? queue;
  final Duration? run;
  final Duration? total;

  TaskTimeouts({
    Duration? queue,
    Duration? run,
    Duration? total,
  })  : queue = _validateOptionalDuration(queue, 'queue'),
        run = _validateOptionalDuration(run, 'run'),
        total = _validateOptionalDuration(total, 'total');
}

/// Task handle for controlling and monitoring a submitted task
///
/// Returned by `FLimit.call` and `FLimitIsolate.isolate` methods.
/// Provides cancellation, status checking, and access to the result.
///
/// Example:
/// ```dart
/// final handle = limit(() => fetchData());
///
/// // Cancel if needed
/// if (shouldCancel) {
///   handle.cancel();
/// }
///
/// // Or await the result
/// try {
///   final result = await handle;
/// } on CanceledException {
///   print('Task was canceled');
/// }
/// ```
class TaskHandle<T> implements Future<T> {
  final int _id;
  final Completer<T> _completer;
  final bool Function(int id)? _onCancel;
  TaskStatus _status = TaskStatus.pending;
  bool _didStart = false;

  TaskHandle._(this._id, this._completer, this._onCancel);

  /// Unique identifier for this task
  int get id => _id;

  /// Whether the task has completed (successfully, with error, or canceled)
  bool get isCompleted => _completer.isCompleted;

  /// Whether the task was canceled
  bool get isCanceled => _status == TaskStatus.canceled;

  /// Whether the task has actually started execution.
  ///
  /// Queue and total timeouts can fail a task before execution begins; in those
  /// cases [status] may be [TaskStatus.failed] while [isStarted] remains false.
  bool get isStarted => _didStart;

  /// Current task status
  TaskStatus get status => _status;

  /// The underlying Future that can be awaited
  ///
  /// Since [TaskHandle] implements [Future], this is equivalent to
  /// awaiting the handle directly.
  Future<T> get future => _completer.future;

  @override
  Stream<T> asStream() => future.asStream();

  @override
  Future<T> catchError(Function onError, {bool Function(Object error)? test}) {
    return future.catchError(onError, test: test);
  }

  /// Cancel this task
  ///
  /// Returns `true` if the task was successfully canceled.
  /// Returns `false` if the task was already completed or started.
  ///
  /// Note: Tasks that have already started executing cannot be canceled.
  /// They will run to completion.
  bool cancel() {
    if (isCanceled || _completer.isCompleted || isStarted) {
      return false;
    }
    final wasCanceled = _onCancel?.call(_id) ?? false;
    if (!wasCanceled) {
      return false;
    }
    return _cancel();
  }

  void _markStarted() {
    if (!_didStart) {
      _didStart = true;
    }
    if (_status == TaskStatus.pending) {
      _status = TaskStatus.running;
    }
  }

  bool _cancel([String message = 'Task was canceled']) {
    if (isCanceled || _completer.isCompleted || isStarted) {
      return false;
    }

    _status = TaskStatus.canceled;
    future.ignore();
    _completer.completeError(CanceledException(message), StackTrace.empty);
    return true;
  }

  void _complete(T value) {
    if (!_completer.isCompleted) {
      _status = TaskStatus.completed;
      _completer.complete(value);
    }
  }

  void _completeError(Object error, StackTrace stackTrace) {
    if (!_completer.isCompleted) {
      _status = TaskStatus.failed;
      _completer.completeError(error, stackTrace);
    }
  }

  @override
  Future<R> then<R>(
    FutureOr<R> Function(T value) onValue, {
    Function? onError,
  }) {
    return future.then(onValue, onError: onError);
  }

  @override
  Future<T> timeout(Duration timeLimit, {FutureOr<T> Function()? onTimeout}) {
    return future.timeout(timeLimit, onTimeout: onTimeout);
  }

  @override
  Future<T> whenComplete(FutureOr<void> Function() action) {
    return future.whenComplete(action);
  }
}

/// Exception thrown when a task is canceled before execution
///
/// This exception is thrown when awaiting a [TaskHandle] that was canceled
/// using [TaskHandle.cancel] before it started executing.
///
/// Example:
/// ```dart
/// final limit = fLimit(1);
///
/// // Block the queue
/// limit(() async => longRunningTask());
///
/// // Queue a task
/// final handle = limit(() async => 'result');
///
/// // Cancel it before it runs
/// handle.cancel();
///
/// try {
///   await handle;
/// } on CanceledException {
///   print('Task was canceled');
/// }
/// ```
class CanceledException implements Exception {
  /// The cancellation message
  final String message;

  /// Creates a canceled exception with the given [message]
  CanceledException(this.message);

  @override
  String toString() => 'CanceledException: $message';
}

/// Exception thrown when a task exceeds its timeout duration
///
/// This exception is thrown when a task configured with `timeout` or
/// [TaskTimeouts] doesn't complete within the specified duration.
///
/// Example:
/// ```dart
/// final limit = fLimit(2);
///
/// final handle = limit(
///   () async {
///     await Future.delayed(Duration(seconds: 10));
///     return 'result';
///   },
///   timeout: Duration(seconds: 1),
/// );
///
/// try {
///   await handle;
/// } on TimeoutException catch (e) {
///   print('Task timed out after ${e.duration}');
/// }
/// ```
class TimeoutException implements Exception {
  /// The timeout duration that was exceeded
  final Duration duration;

  /// The timeout message
  final String message;

  /// The lifecycle phase where the timeout happened.
  final TimeoutStage stage;

  /// Creates a timeout exception with the given [duration] and optional [message]
  TimeoutException(
    this.duration, {
    this.stage = TimeoutStage.run,
    this.message = 'Task timed out',
  });

  @override
  String toString() =>
      'TimeoutException: $message (duration: $duration, stage: $stage)';
}

/// Settled outcome for a task in batch APIs.
class SettledResult<T> {
  final T? value;
  final Object? error;
  final StackTrace? stackTrace;
  final TaskStatus status;

  const SettledResult.success(this.value)
      : error = null,
        stackTrace = null,
        status = TaskStatus.completed;

  const SettledResult.failure(
    this.error,
    this.stackTrace, {
    this.status = TaskStatus.failed,
  }) : value = null;

  bool get isSuccess => status == TaskStatus.completed;

  bool get isFailure => !isSuccess;
}

/// Task wrapper with priority support
///
/// Internal class used to wrap queued tasks with metadata.
class _TaskWrapper<T> {
  final Completer<void> completer;
  final int priority;
  final DateTime createdAt;
  final TaskHandle<T> handle;
  final Future<T> Function() function;
  final Duration? queueTimeout;
  final Duration? runTimeout;
  final Duration? totalTimeout;
  final RetryPolicy? retry;
  Timer? queueTimer;
  Timer? totalTimer;
  Completer<void>? timeoutSignal;

  _TaskWrapper({
    required this.completer,
    required this.handle,
    required this.function,
    this.queueTimeout,
    this.runTimeout,
    this.totalTimeout,
    this.retry,
    this.priority = 0,
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();

  void cancelQueueTimer() {
    queueTimer?.cancel();
    queueTimer = null;
  }

  void cancelPendingTimers() {
    cancelQueueTimer();
    totalTimer?.cancel();
    totalTimer = null;
  }
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
  List<_TaskWrapper> clear();
  _TaskWrapper? removeById(int id);
}

/// FIFO queue implementation
class _FifoQueue implements _TaskQueue {
  final ListQueue<_TaskWrapper> _queue = ListQueue<_TaskWrapper>();

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
  List<_TaskWrapper> clear() {
    final tasks = _queue.toList(growable: false);
    _queue.clear();
    return tasks;
  }

  @override
  _TaskWrapper? removeById(int id) {
    final index = _queue.toList().indexWhere((t) => t.handle.id == id);
    if (index >= 0) {
      final task = _queue.elementAt(index);
      _queue.remove(task);
      return task;
    }
    return null;
  }
}

/// LIFO queue implementation (stack-like)
class _LifoQueue implements _TaskQueue {
  final ListQueue<_TaskWrapper> _queue = ListQueue<_TaskWrapper>();

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
  List<_TaskWrapper> clear() {
    final tasks = _queue.toList(growable: false);
    _queue.clear();
    return tasks;
  }

  @override
  _TaskWrapper? removeById(int id) {
    final index = _queue.toList().indexWhere((t) => t.handle.id == id);
    if (index >= 0) {
      final task = _queue.elementAt(index);
      _queue.remove(task);
      return task;
    }
    return null;
  }
}

/// Priority queue implementation with iterative heap operations
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
  List<_TaskWrapper> clear() {
    final tasks = List<_TaskWrapper>.from(_heap, growable: false);
    _heap.clear();
    return tasks;
  }

  @override
  _TaskWrapper? removeById(int id) {
    final index = _heap.indexWhere((t) => t.handle.id == id);
    if (index < 0) return null;

    final removed = _heap[index];
    final last = _heap.removeLast();
    if (index < _heap.length) {
      _heap[index] = last;
      final parentIndex = (index - 1) ~/ 2;
      if (index > 0 && _shouldSwap(_heap[index], _heap[parentIndex])) {
        _bubbleUp(index);
      } else {
        _bubbleDown(index);
      }
    }
    return removed;
  }

  void _bubbleUp(int index) {
    while (index > 0) {
      final parentIndex = (index - 1) ~/ 2;
      if (!_shouldSwap(_heap[index], _heap[parentIndex])) break;
      _swap(index, parentIndex);
      index = parentIndex;
    }
  }

  void _bubbleDown(int index) {
    while (true) {
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

      if (largest == index) break;
      _swap(index, largest);
      index = largest;
    }
  }

  void _swap(int i, int j) {
    final temp = _heap[i];
    _heap[i] = _heap[j];
    _heap[j] = temp;
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
  final ListQueue<_TaskWrapper> _queue = ListQueue<_TaskWrapper>();
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
  List<_TaskWrapper> clear() {
    final tasks = _queue.toList(growable: false);
    _queue.clear();
    _takeFromHead = true;
    return tasks;
  }

  @override
  _TaskWrapper? removeById(int id) {
    final index = _queue.toList().indexWhere((t) => t.handle.id == id);
    if (index >= 0) {
      final task = _queue.elementAt(index);
      _queue.remove(task);
      return task;
    }
    return null;
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
  List<_TaskWrapper> clear() {
    final tasks = List<_TaskWrapper>.from(_list, growable: false);
    _list.clear();
    return tasks;
  }

  @override
  _TaskWrapper? removeById(int id) {
    final index = _list.indexWhere((t) => t.handle.id == id);
    if (index >= 0) {
      return _list.removeAt(index);
    }
    return null;
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
  bool _isPaused = false;
  bool _isClosed = false;
  int _taskIdCounter = 0;
  final List<Completer<void>> _idleCompleters = [];

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

  /// Whether the limiter is paused
  ///
  /// When paused, no new tasks are started until [resume] is called.
  /// Pending tasks remain in the queue.
  bool get isPaused => _isPaused;

  /// Whether there are no active or pending tasks
  ///
  /// Returns `true` when [activeCount] and [pendingCount] are both zero.
  bool get isEmpty => _activeCount == 0 && _queue.isEmpty;

  /// Whether there are any active tasks
  ///
  /// Returns `true` when [activeCount] is greater than zero.
  bool get isBusy => _activeCount > 0;

  /// Whether the limiter has been closed.
  bool get isClosed => _isClosed;

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
      _tryResumeNext();
    });
  }

  /// Pause the limiter
  ///
  /// When paused, no new tasks are started until [resume] is called.
  /// Tasks already running will continue to completion.
  /// New tasks can still be added to the queue.
  void pause() {
    _isPaused = true;
  }

  /// Resume the limiter
  ///
  /// Resumes processing of queued tasks if the limiter was paused.
  /// If there are pending tasks and available slots, they will start immediately.
  void resume() {
    if (!_isPaused) return;
    _isPaused = false;
    _tryResumeNext();
  }

  /// Clear all pending operations from the queue
  ///
  /// Cancels all queued tasks without executing them. Active operations
  /// are not affected, and pending task handles complete with
  /// [CanceledException].
  ///
  /// Returns the number of queued tasks that were canceled.
  ///
  /// Example:
  /// ```dart
  /// final limit = fLimit(1);
  /// final handles = <TaskHandle<int>>[];
  ///
  /// // Add 100 tasks...
  /// for (var i = 0; i < 100; i++) {
  ///   handles.add(limit(() async => i));
  /// }
  ///
  /// limit.clearQueue(); // Cancel all pending queued tasks
  /// print(limit.pendingCount); // 0
  ///
  /// for (final handle in handles) {
  ///   handle.catchError((_) => -1);
  /// }
  /// ```
  int clearQueue() {
    final clearedTasks = _queue.clear();
    for (final task in clearedTasks) {
      task.cancelPendingTimers();
      task.handle._cancel('Task was canceled because the queue was cleared');
    }
    _notifyIdleIfNeeded();
    return clearedTasks.length;
  }

  /// Execute a function with concurrency limit
  ///
  /// If the concurrency limit has not been reached, the function executes
  /// immediately. Otherwise, it is queued according to the [queueStrategy].
  ///
  /// [priority] is used when [queueStrategy] is [QueueStrategy.priority].
  /// Higher values execute first. Defaults to 0.
  ///
  /// [timeout] if specified, the task will fail with [TimeoutException]
  /// if it doesn't complete within the given duration. This is an alias for
  /// [timeouts].run and is kept for compatibility with earlier APIs.
  /// The underlying operation isn't forcibly canceled, so the concurrency
  /// slot remains occupied until that operation actually finishes.
  ///
  /// [timeouts] provides queue/run/total timeout control. If [timeouts].run is
  /// specified, do not also pass [timeout].
  ///
  /// [retry] if specified, failed tasks will be retried according to the policy.
  ///
  /// Returns a [TaskHandle] that can be used to cancel the task or await the result.
  ///
  /// Example:
  /// ```dart
  /// final handle = limit(() async {
  ///   return fetchData();
  /// });
  ///
  /// final result = await handle;
  ///
  /// // With priority
  /// await limit(() async => criticalTask(), priority: 10);
  ///
  /// // With timeout
  /// await limit(() async => slowTask(), timeout: Duration(seconds: 5));
  ///
  /// // With retry
  /// await limit(() async => unstableTask(), retry: RetryExponential(maxAttempts: 3, baseDelay: Duration(seconds: 1)));
  ///
  /// // With fine-grained timeouts
  /// await limit(
  ///   () async => fetchData(),
  ///   priority: 5,
  ///   timeouts: TaskTimeouts(
  ///     queue: Duration(seconds: 2),
  ///     run: Duration(seconds: 5),
  ///     total: Duration(seconds: 10),
  ///   ),
  /// );
  /// ```
  TaskHandle<T> call<T>(Future<T> Function() function,
      {int priority = 0,
      Duration? timeout,
      RetryPolicy? retry,
      TaskTimeouts? timeouts}) {
    if (_isClosed) {
      throw StateError('Cannot submit new tasks after FLimit has been closed.');
    }

    final resolved = _resolveTaskParameters(
      priority: priority,
      timeout: timeout,
      retry: retry,
      timeouts: timeouts,
    );

    final handle = TaskHandle<T>._(
      _taskIdCounter++,
      Completer<T>(),
      _cancelQueuedTask,
    );

    _enqueue<T>(
      () async => await function(),
      handle,
      priority: resolved.priority,
      queueTimeout: resolved.queueTimeout,
      runTimeout: resolved.runTimeout,
      totalTimeout: resolved.totalTimeout,
      retry: resolved.retry,
    );

    return handle;
  }

  /// Closes the limiter to new work and waits until it becomes idle.
  ///
  /// If [cancelPending] is true, queued tasks are canceled immediately.
  Future<void> close({bool cancelPending = true}) async {
    _isClosed = true;
    if (cancelPending) {
      clearQueue();
    } else {
      _isPaused = false;
      _tryResumeNext();
    }
    await onIdle;
  }

  /// Alias for [close].
  Future<void> dispose({bool cancelPending = true}) {
    return close(cancelPending: cancelPending);
  }

  void _enqueue<T>(Future<T> Function() function, TaskHandle<T> handle,
      {int priority = 0,
      Duration? queueTimeout,
      Duration? runTimeout,
      Duration? totalTimeout,
      RetryPolicy? retry}) {
    final internalCompleter = Completer<void>();
    final taskWrapper = _TaskWrapper<T>(
      completer: internalCompleter,
      handle: handle,
      function: function,
      queueTimeout: queueTimeout,
      runTimeout: runTimeout,
      totalTimeout: totalTimeout,
      retry: retry,
      priority: priority,
    );

    _queue.add(taskWrapper);
    _armPendingTimeouts(taskWrapper);

    internalCompleter.future.then((_) async {
      await _run(taskWrapper);
    });

    // Check if we can start processing immediately
    scheduleMicrotask(() {
      _tryResumeNext();
    });
  }

  Future<void> _run<T>(_TaskWrapper<T> taskWrapper) async {
    final runTimeout = taskWrapper.runTimeout;
    final retry = taskWrapper.retry;
    Timer? runTimeoutTimer;

    try {
      taskWrapper.cancelQueueTimer();
      taskWrapper.handle._markStarted();
      taskWrapper.timeoutSignal ??= Completer<void>();

      if (taskWrapper.handle.isCompleted) {
        return;
      }

      if (runTimeout == Duration.zero) {
        _failRunningTask(taskWrapper, Duration.zero, TimeoutStage.run);
        return;
      }

      if (runTimeout != null) {
        runTimeoutTimer = Timer(runTimeout, () {
          _failRunningTask(taskWrapper, runTimeout, TimeoutStage.run);
        });
      }

      var attempt = 0;
      while (true) {
        try {
          final result = await taskWrapper.function();
          if (!taskWrapper.handle.isCompleted) {
            taskWrapper.handle._complete(result);
          }
          return;
        } catch (error, stackTrace) {
          if (taskWrapper.handle.isCompleted) {
            return;
          }

          if (retry == null || !retry.shouldRetry(attempt, error, stackTrace)) {
            taskWrapper.handle._completeError(error, stackTrace);
            return;
          }

          final delay = retry.nextDelay(attempt, error, stackTrace);
          attempt++;

          if (delay == null || delay <= Duration.zero) {
            continue;
          }

          if (taskWrapper.timeoutSignal != null) {
            await Future.any<void>([
              Future<void>.delayed(delay),
              taskWrapper.timeoutSignal!.future,
            ]);

            if (taskWrapper.handle.isCompleted) {
              return;
            }
            continue;
          }

          await Future<void>.delayed(delay);
        }
      }
    } finally {
      runTimeoutTimer?.cancel();
      taskWrapper.cancelPendingTimers();
      _next();
    }
  }

  void _tryResumeNext() {
    if (_isPaused) return;
    while (_activeCount < _concurrency && _queue.isNotEmpty) {
      _resumeNext();
    }
  }

  void _resumeNext() {
    if (_isPaused || _activeCount >= _concurrency || _queue.isEmpty) return;

    final taskWrapper = _queue.removeNext();
    if (taskWrapper.handle.isCanceled) {
      _notifyIdleIfNeeded();
      return;
    }

    _activeCount++;
    taskWrapper.completer.complete();
  }

  void _next() {
    _activeCount--;
    _notifyIdleIfNeeded();
    _tryResumeNext();
  }

  void _notifyIdleIfNeeded() {
    if (_activeCount == 0 && _queue.isEmpty) {
      for (final completer in _idleCompleters) {
        if (!completer.isCompleted) {
          completer.complete();
        }
      }
      _idleCompleters.clear();
    }
  }

  bool _cancelQueuedTask(int id) {
    final task = _queue.removeById(id);
    if (task == null) {
      return false;
    }

    task.cancelPendingTimers();
    _notifyIdleIfNeeded();
    return true;
  }

  void _armPendingTimeouts<T>(_TaskWrapper<T> taskWrapper) {
    final queueTimeout = taskWrapper.queueTimeout;
    if (queueTimeout != null) {
      if (queueTimeout == Duration.zero) {
        scheduleMicrotask(() {
          _failPendingTask(taskWrapper, queueTimeout, TimeoutStage.queue);
        });
      } else {
        taskWrapper.queueTimer = Timer(queueTimeout, () {
          _failPendingTask(taskWrapper, queueTimeout, TimeoutStage.queue);
        });
      }
    }

    final totalTimeout = taskWrapper.totalTimeout;
    if (totalTimeout != null) {
      if (totalTimeout == Duration.zero) {
        scheduleMicrotask(() {
          _failTask(taskWrapper, totalTimeout, TimeoutStage.total);
        });
      } else {
        taskWrapper.totalTimer = Timer(totalTimeout, () {
          _failTask(taskWrapper, totalTimeout, TimeoutStage.total);
        });
      }
    }
  }

  void _failPendingTask<T>(
      _TaskWrapper<T> taskWrapper, Duration duration, TimeoutStage stage) {
    if (taskWrapper.handle.isCompleted) {
      return;
    }

    final removed = _queue.removeById(taskWrapper.handle.id);
    if (removed == null) {
      return;
    }

    removed.cancelPendingTimers();
    removed.handle._completeError(
      TimeoutException(duration, stage: stage),
      StackTrace.empty,
    );
    _notifyIdleIfNeeded();
  }

  void _failRunningTask<T>(
      _TaskWrapper<T> taskWrapper, Duration duration, TimeoutStage stage) {
    if (taskWrapper.handle.isCompleted) {
      return;
    }

    if (taskWrapper.timeoutSignal != null &&
        !taskWrapper.timeoutSignal!.isCompleted) {
      taskWrapper.timeoutSignal!.complete();
    }

    taskWrapper.handle._completeError(
      TimeoutException(duration, stage: stage),
      StackTrace.empty,
    );
  }

  void _failTask<T>(
      _TaskWrapper<T> taskWrapper, Duration duration, TimeoutStage stage) {
    if (taskWrapper.handle.isCompleted) {
      return;
    }

    final removed = _queue.removeById(taskWrapper.handle.id);
    if (removed != null) {
      removed.cancelPendingTimers();
      removed.handle._completeError(
        TimeoutException(duration, stage: stage),
        StackTrace.empty,
      );
      _notifyIdleIfNeeded();
      return;
    }

    _failRunningTask(taskWrapper, duration, stage);
  }

  void _validateConcurrency(int concurrency) {
    if (concurrency <= 0 || !concurrency.isFinite) {
      throw ArgumentError('Expected concurrency to be a number from 1 and up');
    }
  }

  /// Returns a Future that completes when the queue is empty and active count is 0.
  ///
  /// Uses event-based notification for efficiency (no polling).
  ///
  /// If the limiter is already idle, returns a completed Future immediately.
  ///
  /// Example:
  /// ```dart
  /// final limit = fLimit(2);
  ///
  /// // Add tasks...
  /// for (int i = 0; i < 10; i++) {
  ///   limit(() async => processItem(i));
  /// }
  ///
  /// // Wait for all to finish
  /// await limit.onIdle;
  /// print('All tasks completed!');
  /// ```
  Future<void> get onIdle {
    if (isEmpty) {
      return Future.value();
    }

    final completer = Completer<void>();
    _idleCompleters.add(completer);
    return completer.future;
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

class _ResolvedTaskParameters {
  final int priority;
  final Duration? queueTimeout;
  final Duration? runTimeout;
  final Duration? totalTimeout;
  final RetryPolicy? retry;

  const _ResolvedTaskParameters({
    required this.priority,
    required this.queueTimeout,
    required this.runTimeout,
    required this.totalTimeout,
    required this.retry,
  });
}

_ResolvedTaskParameters _resolveTaskParameters({
  required int priority,
  required Duration? timeout,
  required RetryPolicy? retry,
  required TaskTimeouts? timeouts,
}) {
  if (timeout != null && timeouts?.run != null) {
    throw ArgumentError(
      'Use either timeout or timeouts.run, not both.',
    );
  }

  return _ResolvedTaskParameters(
    priority: priority,
    queueTimeout: timeouts?.queue,
    runTimeout: timeouts?.run ?? timeout,
    totalTimeout: timeouts?.total,
    retry: retry,
  );
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
