# 🚦 f_limit

[![pub package](https://img.shields.io/pub/v/f_limit.svg)](https://pub.dev/packages/f_limit)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Dart CI](https://github.com/fluttercandies/f_limit/workflows/Dart%20CI/badge.svg)](https://github.com/fluttercandies/f_limit/actions)

适用于 Dart 的异步并发限制器，提供发布级的并发控制能力。

**中文文档** | **[English](README.md)**

---

## 📦 安装

```yaml
dependencies:
  f_limit: ^2.0.0
```

```bash
dart pub get
```

---

## ⚡ 快速开始

```dart
import 'package:f_limit/f_limit.dart';

void main() async {
  final limit = fLimit(2); // 最多同时执行 2 个任务

  final handles = List.generate(5, (i) => limit(() async {
    await Future.delayed(Duration(seconds: 1));
    return i;
  }));

  final results = await Future.wait(handles);
  print('完成: $results'); // [0, 1, 2, 3, 4]
}
```

`TaskHandle<T>` 实现了 `Future<T>`，因此 1.x 中常见的 `await limit(...)` 和
`Future.wait([...handles])` 写法在 2.0 仍然可用。

---

## 🎯 核心特性

| 特性 | 说明 |
|------|------|
| `TaskHandle` | 支持取消、状态查询和结果获取 |
| 队列策略 | FIFO、LIFO、Priority、Alternating、Random |
| 超时控制 | 单任务超时失败 |
| 重试策略 | 内置简单重试、固定间隔、指数退避、抖动 |
| 暂停 / 恢复 | 可暂停调度并恢复 |
| Isolate | 支持 CPU 密集型任务隔离执行 |

---

## 📋 队列策略

| 策略 | 枚举值 | 说明 |
|------|--------|------|
| FIFO | `QueueStrategy.fifo` | 先进先出 |
| LIFO | `QueueStrategy.lifo` | 后进先出 |
| Priority | `QueueStrategy.priority` | 高优先级先执行 |
| Alternating | `QueueStrategy.alternating` | 头尾交替调度 |
| Random | `QueueStrategy.random` | 随机挑选等待任务 |

```dart
final limit = fLimit(2, queueStrategy: QueueStrategy.priority);
```

---

## 📖 API 概览

### 创建 limiter

```dart
final limit = fLimit(concurrency, queueStrategy: QueueStrategy.fifo);
```

### 常用属性

| 属性 | 类型 | 说明 |
|------|------|------|
| `activeCount` | `int` | 当前执行中的任务数 |
| `pendingCount` | `int` | 当前排队中的任务数 |
| `concurrency` | `int` | 最大并发数，可运行时修改 |
| `queueStrategy` | `QueueStrategy` | 当前队列策略 |
| `isPaused` | `bool` | 是否暂停调度 |
| `isClosed` | `bool` | 关闭后是否拒绝新任务 |
| `isEmpty` | `bool` | 是否没有活动和排队任务 |
| `isBusy` | `bool` | 是否存在活动任务 |

### 常用方法

```dart
TaskHandle<T> call<T>(
  Future<T> Function() fn, {
  int priority = 0,
  Duration? timeout,
  TaskTimeouts? timeouts,
  RetryPolicy? retry,
});

TaskHandle<T> isolate<T>(
  FutureOr<T> Function() fn, {
  int priority = 0,
  Duration? timeout,
  TaskTimeouts? timeouts,
  RetryPolicy? retry,
});

void pause();
void resume();
int clearQueue();
Future<void> close({bool cancelPending = true});
Future<void> dispose({bool cancelPending = true});
Future<void> get onIdle;
```

`clearQueue()` 会取消所有尚未开始的排队任务，这些任务对应的 handle 会以
`CanceledException` 结束，并返回本次取消的任务数量。

`timeout` 是 `timeouts?.run` 的兼容别名；不要同时传 `timeout` 和
`timeouts.run`。

---

## 🎯 示例

### TaskHandle

```dart
final limit = fLimit(2);

final handle = limit(() async {
  await Future.delayed(Duration(seconds: 1));
  return 'result';
});

print(handle.isCompleted); // false
print(handle.isStarted);   // false

await Future<void>.delayed(Duration.zero);
print(handle.isStarted);   // true

final result = await handle;
print(result); // result
```

### 取消排队任务

```dart
final limit = fLimit(1);

limit(() async => longOperation());
final handle = limit(() async => 'will be canceled');

if (!handle.isStarted && handle.cancel()) {
  try {
    await handle;
  } on CanceledException {
    print('任务已取消');
  }
}
```

### 超时

```dart
final limit = fLimit(2);

final handle = limit(
  () async => fetchData(),
  timeout: Duration(seconds: 5),
);

try {
  await handle;
} on TimeoutException {
  print('任务超时');
}
```

`timeout` 只影响返回给调用方的 handle 结果，不会强制终止底层操作；
为了保证并发上限真实有效，limiter 会一直占用这个并发槽位，直到该操作实际结束。

如果任务是在真正开始执行前失败的，例如队列等待超时，或仍处于排队阶段时触发
了 total timeout，那么 `handle.status` 会是 `TaskStatus.failed`，但
`handle.isStarted` 仍然保持 `false`。

如果需要更细的超时控制，可以使用 `TaskTimeouts`：

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
  print(e.stage); // queue / run / total
}
```

### 重试

```dart
final limit = fLimit(2);

final result = await limit(
  () async => unstableApi(),
  retry: RetryExponential(
    maxAttempts: 5,
    baseDelay: Duration(seconds: 1),
    multiplier: 2.0,
    maxDelay: Duration(minutes: 1),
  ),
);
```

### 等待所有任务完成

```dart
final limit = fLimit(3);

for (final item in [1, 2, 3, 4, 5]) {
  limit(() async => processItem(item));
}

await limit.onIdle;
print('全部完成');
```

### Settled 批处理

```dart
final settled = await limit.mapSettled([1, 2, 3], (n) async {
  if (n == 2) throw StateError('boom');
  return n * 2;
});

for (final result in settled) {
  print(result.status);
}
```

### 关闭 limiter

```dart
final limit = fLimit(2);

limit(() async => processItem(1));
limit(() async => processItem(2));

await limit.close(cancelPending: false); // 排空队列后关闭
print(limit.isClosed); // true
```

---

## 📄 许可证

MIT © [FlutterCandies](https://github.com/fluttercandies)
