# 🚦 f_limit

[![pub package](https://img.shields.io/pub/v/f_limit.svg)](https://pub.dev/packages/f_limit)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Dart CI](https://github.com/fluttercandies/f_limit/workflows/Dart%20CI/badge.svg)](https://github.com/fluttercandies/f_limit/actions)

Dart concurrency limiter for async operations with advanced features.

**[中文文档](README_CN.md)**

---

## 📦 Install

```yaml
dependencies:
  f_limit: ^2.0.0
```

```bash
dart pub get
```

---

## ⚡ Quick Start

```dart
import 'package:f_limit/f_limit.dart';

void main() async {
  final limit = fLimit(2); // Max 2 concurrent operations

  final handles = List.generate(5, (i) => limit(() async {
    await Future.delayed(Duration(seconds: 1));
    return i;
  }));

  final results = await Future.wait(handles);
  print('Done: $results'); // [0, 1, 2, 3, 4]
}
```

---

## 🎯 Core Features

| Feature | Description |
|---------|-------------|
| **TaskHandle** | Control tasks with cancel, status, and result access |
| **Queue Strategies** | FIFO, LIFO, Priority, Alternating, Random |
| **Timeout** | Auto-fail tasks that exceed time limits |
| **Retry** | Built-in retry policies with exponential backoff |
| **Pause/Resume** | Suspend and resume task processing |
| **Isolate** | Run CPU-intensive tasks in separate isolates |

---

## 📋 Queue Strategies

| Strategy | Enum Value | Description | Use Case |
|----------|------------|-------------|----------|
| FIFO | `QueueStrategy.fifo` | First In, First Out | Default, fair execution |
| LIFO | `QueueStrategy.lifo` | Last In, First Out | Stack-like, newest first |
| Priority | `QueueStrategy.priority` | Priority-based | Important tasks first |
| Alternating | `QueueStrategy.alternating` | Head → Tail → Head... | Two-way fair scheduling |
| Random | `QueueStrategy.random` | Random selection | Load balancing |

```dart
final limit = fLimit(2, queueStrategy: QueueStrategy.priority);
```

---

## 📖 API Reference

### Constructor

```dart
final limit = fLimit(concurrency, {queueStrategy});
```

### Properties

| Property | Type | Description |
|----------|------|-------------|
| `activeCount` | `int` | Currently executing |
| `pendingCount` | `int` | In queue |
| `concurrency` | `int` | Max concurrent (get/set) |
| `queueStrategy` | `QueueStrategy` | Current strategy |
| `isPaused` | `bool` | Is limiter paused |
| `isClosed` | `bool` | Rejects new work after close/dispose |
| `isEmpty` | `bool` | No active or pending |
| `isBusy` | `bool` | Has active tasks |

### Methods

```dart
// Execute task
TaskHandle<T> call<T>(
  Future<T> Function() fn, {
  int priority = 0,
  Duration? timeout,
  TaskTimeouts? timeouts,
  RetryPolicy? retry,
});

// Run in isolate
TaskHandle<T> isolate<T>(
  FutureOr<T> Function() fn, {
  int priority = 0,
  Duration? timeout,
  TaskTimeouts? timeouts,
  RetryPolicy? retry,
});

// Control
void pause();
void resume();
int clearQueue();
Future<void> close({bool cancelPending = true});
Future<void> dispose({bool cancelPending = true});

// Wait for idle
Future<void> get onIdle;
```

`clearQueue()` cancels queued tasks that have not started yet and returns the
number of canceled tasks. Awaiting those handles completes with
`CanceledException`.

`timeout` is an alias for `timeouts?.run`. Do not pass both `timeout` and
`timeouts.run` at the same time.

---

## 🎯 Examples

### TaskHandle - Control Tasks

```dart
final limit = fLimit(2);

// Get handle for task control
final handle = limit(() async {
  await Future.delayed(Duration(seconds: 1));
  return 'result';
});

// Check status
print(handle.isCompleted); // false
print(handle.isStarted);   // false

await Future<void>.delayed(Duration.zero);
print(handle.isStarted);   // true

// Get result
final result = await handle;
print(handle.isCompleted); // true
```

### Cancel Tasks

```dart
final limit = fLimit(1);

// Start long task
limit(() async => longOperation());

// Queue another task
final handle = limit(() async => 'will be canceled');

// Cancel if still pending
if (!handle.isStarted && handle.cancel()) {
  print(handle.isCanceled); // true

  try {
    await handle;
  } on CanceledException {
    print('Task was canceled');
  }
}
```

### Timeout

```dart
final limit = fLimit(2);

final handle = limit(
  () async => fetchData(),
  timeout: Duration(seconds: 5),
);

try {
  await handle;
} on TimeoutException {
  print('Task timed out!');
}
```

`timeout` only affects the returned handle. It does not forcibly stop the
underlying operation, and the limiter keeps that concurrency slot occupied
until the operation actually finishes.

If a task fails before execution starts, such as a queue timeout or a total
timeout while still pending, `handle.status` becomes `TaskStatus.failed` but
`handle.isStarted` remains `false`.

For finer control, use `TaskTimeouts`:

```dart
final handle = limit(
  () async => fetchData(),
  timeouts: TaskTimeouts(
    queue: Duration(seconds: 2),
    run: Duration(seconds: 5),
    total: Duration(seconds: 10),
  ),
);

try {
  await handle;
} on TimeoutException catch (e) {
  print(e.stage); // queue, run, or total
}
```

### Retry Policies

```dart
final limit = fLimit(2);

// Simple retry (no delay)
final handle1 = limit(
  () async => unstableApi(),
  retry: RetrySimple(maxAttempts: 3),
);

// Fixed delay
final handle2 = limit(
  () async => unstableApi(),
  retry: RetryFixed(maxAttempts: 3, delay: Duration(seconds: 1)),
);

// Exponential backoff
final handle3 = limit(
  () async => unstableApi(),
  retry: RetryExponential(
    maxAttempts: 5,
    baseDelay: Duration(seconds: 1),
    multiplier: 2.0,
    maxDelay: Duration(minutes: 1),
  ),
);

// With jitter
final handle4 = limit(
  () async => unstableApi(),
  retry: RetryWithJitter(
    RetryExponential(maxAttempts: 3, baseDelay: Duration(seconds: 1)),
    jitterFactor: 0.5,
  ),
);
```

### Priority Queue

```dart
final limit = fLimit(1, queueStrategy: QueueStrategy.priority);

limit(() => print('🔴 Critical'), priority: 10);
limit(() => print('🟡 Normal'), priority: 5);
limit(() => print('🟢 Background'), priority: 1);

// Output: 🔴 🟡 🟢
```

### Pause and Resume

```dart
final limit = fLimit(2);

// Add tasks
for (int i = 0; i < 10; i++) {
  limit(() async => processItem(i));
}

// Pause - stops processing new tasks
limit.pause();
print(limit.isPaused); // true

// Resume - continues processing
limit.resume();
print(limit.isPaused); // false
```

### Isolate for CPU-Intensive Work

```dart
final limit = fLimit(2);

final handle = limit.isolate(() {
  // Heavy computation runs in separate isolate
  int sum = 0;
  for (int i = 0; i < 1000000; i++) {
    sum += i;
  }
  return sum;
});

final result = await handle;
print(result); // 499999500000
```

### Extension Methods

```dart
final limit = fLimit(3);

// Concurrent mapping
final results = await limit.map([1, 2, 3, 4, 5], (n) async => n * 2);
print(results); // [2, 4, 6, 8, 10]

// Concurrent filtering
final evens = await limit.filter([1, 2, 3, 4, 5], (n) async => n % 2 == 0);
print(evens); // [2, 4]

// Concurrent iteration
final items = ['a', 'b', 'c'];
await limit.forEach(items, (item) async => processItem(item));

// Wait for idle
await limit.onIdle;
print('All tasks completed!');
```

For batch work that should not fail fast, use settled APIs:

```dart
final settled = await limit.mapSettled([1, 2, 3], (n) async {
  if (n == 2) throw StateError('boom');
  return n * 2;
});

for (final result in settled) {
  print(result.status);
}
```

### Close and Dispose

```dart
final limit = fLimit(2);

limit(() async => processItem(1));
limit(() async => processItem(2));

await limit.close(cancelPending: false); // drain queued work, reject new work
print(limit.isClosed); // true
```

`TaskHandle<T>` implements `Future<T>`, so existing code like `await limit(...)`
and `Future.wait([...handles])` remains valid in 2.0.

---

## 📄 License

MIT © [FlutterCandies](https://github.com/fluttercandies)
