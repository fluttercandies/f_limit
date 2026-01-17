# 🚦 f_limit

[![pub package](https://img.shields.io/pub/v/f_limit.svg)](https://pub.dev/packages/f_limit)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)

Dart concurrency limiter for async operations.

**[中文文档](README_CN.md)**

---

## 📦 Install

```yaml
dependencies:
  f_limit: ^1.0.0
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

  final tasks = List.generate(5, (i) => () async {
    await Future.delayed(Duration(seconds: 1));
    return i;
  });

  final results = await Future.wait(tasks.map((task) => limit(task)));
  print('Done: $results');
}
```

---

## 📋 Queue Strategies

| Strategy | Description | Use Case |
|----------|-------------|----------|
| `fifo` | First In, First Out | Default, fair execution |
| `lifo` | Last In, First Out | Stack-like, newest first |
| `priority` | Priority-based | Important tasks first |
| `alternating` | Head → Tail → Head... | Two-way fair scheduling |
| `random` | Random selection | Load balancing |

```dart
final limit = fLimit(2, queueStrategy: QueueStrategy.priority);
```

---

## 📖 API

### Constructor

| Method | Description |
|--------|-------------|
| `fLimit(concurrency, {queueStrategy})` | Create limiter |

### Properties

| Property | Type | Description |
|----------|------|-------------|
| `activeCount` | `int` | Currently executing |
| `pendingCount` | `int` | In queue |
| `concurrency` | `int` | Max concurrent (get/set) |
| `queueStrategy` | `QueueStrategy` | Current strategy |

### Methods

| Method | Description |
|--------|-------------|
| `call(fn, {priority})` | Execute with limit |
| `clearQueue()` | Clear pending tasks |
| `isolate(fn, {priority})` | Run in isolate |
| `map(items, mapper)` | Concurrent mapping |
| `onIdle` | Wait for completion |

---

## 🎯 Examples

### Priority Queue

```dart
final limit = fLimit(1, queueStrategy: QueueStrategy.priority);

limit(() => print('🔴 Critical'), priority: 10);
limit(() => print('🟡 Normal'), priority: 5);
limit(() => print('🟢 Background'), priority: 1);

// Output: 🔴 🟡 🟢
```

### Dynamic Concurrency

```dart
final limit = fLimit(1);

limit.concurrency = 5; // Increase at runtime
print('Max concurrent: ${limit.concurrency}');
```

### Clear Queue

```dart
final limit = fLimit(1);

// Add many tasks...
for (int i = 0; i < 100; i++) {
  limit(() async => i);
}

print('Pending: ${limit.pendingCount}'); // 99
limit.clearQueue();
print('Pending: ${limit.pendingCount}'); // 0
```

---

## 📄 License

MIT © [FlutterCandies](https://github.com/fluttercandies)
