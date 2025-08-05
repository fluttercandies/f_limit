# 🚦 f_limit

[![pub package](https://img.shields.io/pub/v/f_limit.svg)](https://pub.dev/packages/f_limit)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)

A Dart implementation of [p-limit](https://github.com/sindresorhus/p-limit) for controlling the concurrency of async operations.

**[中文文档](README_CN.md)** | **English**

## ✨ Features

- 🔢 **Concurrency Control** - Limit the number of concurrent async operations
- 🎛️ **Dynamic Adjustment** - Change concurrency limits on the fly
- 📊 **Queue Management** - Track active and pending operations
- 🚀 **Multiple Queue Strategies** - FIFO, LIFO, and Priority-based execution
- ⚡ **High Performance** - Efficient queue implementations
- 🛡️ **Error Handling** - Proper error propagation and handling
- 📦 **Easy to Use** - Simple and intuitive API
- 🎯 **Type Safe** - Full Dart type safety support

## 🚀 Quick Start

### Installation

Add this to your `pubspec.yaml`:

```yaml
dependencies:
  f_limit: ^1.0.0
```

Then run:

```bash
dart pub get
```

### Basic Usage

```dart
import 'package:f_limit/f_limit.dart';

void main() async {
  // 🔧 Create a limiter that allows only 2 concurrent operations
  final limit = fLimit(2);
  
  // 📝 Create some async tasks
  final tasks = List.generate(5, (i) => () async {
    print('🚀 Task $i started');
    await Future.delayed(Duration(seconds: 1));
    print('✅ Task $i completed');
    return 'Result $i';
  });
  
  // ⚡ Execute all tasks with concurrency limit
  final futures = tasks.map((task) => limit(task));
  final results = await Future.wait(futures);
  
  print('🎉 All tasks completed: $results');
}
```

## 📚 Usage Examples

### 🌐 API Rate Limiting

```dart
import 'package:f_limit/f_limit.dart';

Future<String> fetchData(String url) async {
  // Simulate API call
  await Future.delayed(Duration(milliseconds: 200));
  return 'Data from $url';
}

void main() async {
  // 🛡️ Limit API calls to 3 concurrent requests
  final limit = fLimit(3);
  
  final urls = [
    'https://api.example.com/users',
    'https://api.example.com/posts',
    'https://api.example.com/comments',
    'https://api.example.com/albums',
    'https://api.example.com/photos',
  ];
  
  // 🚀 Execute API calls with rate limiting
  final futures = urls.map((url) => limit(() => fetchData(url)));
  final results = await Future.wait(futures);
  
  print('📊 API Results: $results');
}
```

### 🎛️ Dynamic Concurrency Control

```dart
void main() async {
  final limit = fLimit(1);
  
  // 📝 Start with limited concurrency
  final futures = <Future<String>>[];
  for (int i = 0; i < 10; i++) {
    futures.add(limit(() async {
      print('🔄 Task $i (concurrency: ${limit.concurrency})');
      await Future.delayed(Duration(milliseconds: 100));
      return 'Task $i done';
    }));
  }
  
  // 🚀 Increase concurrency after some time
  Future.delayed(Duration(milliseconds: 300), () {
    print('⬆️ Increasing concurrency to 5');
    limit.concurrency = 5;
  });
  
  await Future.wait(futures);
  print('🎉 All tasks completed');
}
```

### 📋 Queue Strategies

#### 🔄 FIFO (First In, First Out) - Default

```dart
final limit = fLimit(2, queueStrategy: QueueStrategy.fifo);
// Tasks execute in the order they were added
```

#### 📚 LIFO (Last In, First Out)

```dart
final limit = fLimit(2, queueStrategy: QueueStrategy.lifo);
// Tasks execute in reverse order (stack-like behavior)
```

#### ⭐ Priority Queue

```dart
final limit = fLimit(2, queueStrategy: QueueStrategy.priority);

// 🎯 Add tasks with different priorities
limit(() async {
  print('🔵 Background task');
}, priority: 1);

limit(() async {
  print('🔴 Critical task');
}, priority: 10);

limit(() async {
  print('🟡 Important task');
}, priority: 5);

// ⚡ Execution order: Critical (10), Important (5), Background (1)
```

### 🏆 Priority-based Task Management

```dart
void main() async {
  final limit = fLimit(1, queueStrategy: QueueStrategy.priority);
  
  final futures = <Future<void>>[];
  
  // 🟢 Low priority
  futures.add(limit(() async {
    print('🟢 Background maintenance');
  }, priority: 1));
  
  // 🟡 Medium priority  
  futures.add(limit(() async {
    print('🟡 User notification');
  }, priority: 5));
  
  // 🔴 High priority
  futures.add(limit(() async {
    print('🔴 Critical security update');
  }, priority: 10));
  
  await Future.wait(futures);
  // Output: 🔴 🟡 🟢
}
```

## 📖 API Reference

### 🔧 `fLimit(int concurrency, {QueueStrategy queueStrategy})`

Creates a concurrency limiter.

**Parameters:**
- `concurrency` - Maximum number of concurrent operations (≥ 1)
- `queueStrategy` - Queue execution strategy (optional, defaults to FIFO)

**Returns:** `FLimit` instance

### 📊 `QueueStrategy`

Queue execution strategies:

| Strategy | Description | Use Case |
|----------|-------------|----------|
| `fifo` | First In, First Out | 📋 Fair task execution |
| `lifo` | Last In, First Out | 📚 Stack-like processing |
| `priority` | Priority-based | ⭐ Important tasks first |

### 🏗️ `FLimit` Class

#### Properties

- `activeCount` - 🔄 Number of currently executing operations
- `pendingCount` - ⏳ Number of queued operations  
- `concurrency` - 🎛️ Current concurrency limit (get/set)
- `queueStrategy` - 📋 Current queue strategy

#### Methods

- `call(function, {priority})` - 🚀 Execute function with concurrency limit
- `clearQueue()` - 🗑️ Clear all pending operations

### 🔗 `limitFunction<T>(function, options)`

Creates a limited version of a function.

**Parameters:**
- `function` - The function to limit
- `options` - `LimitOptions` with concurrency and queue strategy

**Returns:** Limited function wrapper

## 🛡️ Error Handling

The limiter properly handles errors in async operations:

```dart
final limit = fLimit(2);

final future1 = limit(() async {
  throw Exception('💥 Something went wrong');
});

final future2 = limit(() async {
  return '✅ Success';
});

try {
  await future1; // This will throw
} catch (e) {
  print('❌ Caught error: $e');
}

final result = await future2; // This will succeed
print('✅ Result: $result');
```

## 🔍 Monitoring and Debugging

```dart
final limit = fLimit(3);

// 📊 Monitor queue status
print('Active: ${limit.activeCount}');
print('Pending: ${limit.pendingCount}');
print('Strategy: ${limit.queueStrategy}');

// 🔧 Add tasks and monitor
for (int i = 0; i < 10; i++) {
  limit(() async {
    print('📊 Active: ${limit.activeCount}, Pending: ${limit.pendingCount}');
    await Future.delayed(Duration(milliseconds: 100));
  });
}
```

## 🆚 Comparison with JavaScript p-limit

| JavaScript | Dart | Description |
|------------|------|-------------|
| `const limit = pLimit(2)` | `final limit = fLimit(2)` | 🔧 Create limiter |
| `limit(() => asyncTask())` | `limit(() => asyncTask())` | 🚀 Execute task |
| `limit.activeCount` | `limit.activeCount` | 📊 Active count |
| `limit.pendingCount` | `limit.pendingCount` | ⏳ Pending count |
| `limit.clearQueue()` | `limit.clearQueue()` | 🗑️ Clear queue |

## 🎯 Advanced Examples

### 📁 File Processing with Priority

```dart
enum TaskPriority {
  low(1),
  medium(5), 
  high(10);
  
  const TaskPriority(this.value);
  final int value;
}

Future<void> processFiles() async {
  final limit = fLimit(3, queueStrategy: QueueStrategy.priority);
  
  // 🔴 Critical system files
  limit(() => processFile('system.log'), priority: TaskPriority.high.value);
  
  // 🟡 User documents  
  limit(() => processFile('document.pdf'), priority: TaskPriority.medium.value);
  
  // 🟢 Cache files
  limit(() => processFile('cache.tmp'), priority: TaskPriority.low.value);
}
```

### 🌊 Batch Processing

```dart
Future<void> batchProcess(List<String> items) async {
  final limit = fLimit(5);
  
  await Future.wait(
    items.map((item) => limit(() => processItem(item)))
  );
  
  print('🎉 Batch processing completed!');
}
```

## 🤝 Contributing

We welcome contributions! 

## 📄 License

This project is licensed under the MIT License - see the [LICENSE](https://github.com/fluttercandies/f_limit/blob/main/LICENSE) file for details.

## 🙏 Acknowledgements

- Inspired by [p-limit](https://github.com/sindresorhus/p-limit) by Sindre Sorhus
- Part of the [FlutterCandies](https://github.com/fluttercandies) organization

---

<div align="center">

**[🏠 FlutterCandies](https://github.com/fluttercandies) | [📦 pub.dev](https://pub.dev/packages/f_limit) | [🐛 Issues](https://github.com/fluttercandies/f_limit/issues)**

Made with ❤️ by the FlutterCandies team

</div>
