# 🚦 f_limit

[![pub package](https://img.shields.io/pub/v/f_limit.svg)](https://pub.dev/packages/f_limit)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)

一个用于控制异步操作并发数的 Dart 实现，基于 [p-limit](https://github.com/sindresorhus/p-limit)。

**中文文档** | **[English](README.md)**

## ✨ 特性

- 🔢 **并发控制** - 限制同时执行的异步操作数量
- 🎛️ **动态调整** - 运行时动态修改并发限制
- 📊 **队列管理** - 追踪活跃和等待中的操作
- 🚀 **多种队列策略** - 支持 FIFO、LIFO 和优先级队列
- ⚡ **高性能** - 高效的队列实现
- 🛡️ **错误处理** - 完善的错误传播和处理机制
- 📦 **易于使用** - 简单直观的 API 设计
- 🎯 **类型安全** - 完整的 Dart 类型安全支持

## 🚀 快速开始

### 安装

在 `pubspec.yaml` 中添加依赖：

```yaml
dependencies:
  f_limit: ^1.0.0
```

然后运行：

```bash
dart pub get
```

### 基础用法

```dart
import 'package:f_limit/f_limit.dart';

void main() async {
  // 🔧 创建一个最多允许 2 个并发操作的限制器
  final limit = fLimit(2);
  
  // 📝 创建一些异步任务
  final tasks = List.generate(5, (i) => () async {
    print('🚀 任务 $i 开始');
    await Future.delayed(Duration(seconds: 1));
    print('✅ 任务 $i 完成');
    return '结果 $i';
  });
  
  // ⚡ 使用并发限制执行所有任务
  final futures = tasks.map((task) => limit(task));
  final results = await Future.wait(futures);
  
  print('🎉 所有任务完成：$results');
}
```

## 📚 使用示例

### 🌐 API 速率限制

```dart
import 'package:f_limit/f_limit.dart';

Future<String> fetchData(String url) async {
  // 模拟 API 调用
  await Future.delayed(Duration(milliseconds: 200));
  return '来自 $url 的数据';
}

void main() async {
  // 🛡️ 限制 API 调用最多 3 个并发请求
  final limit = fLimit(3);
  
  final urls = [
    'https://api.example.com/users',
    'https://api.example.com/posts',
    'https://api.example.com/comments',
    'https://api.example.com/albums',
    'https://api.example.com/photos',
  ];
  
  // 🚀 使用速率限制执行 API 调用
  final futures = urls.map((url) => limit(() => fetchData(url)));
  final results = await Future.wait(futures);
  
  print('📊 API 结果：$results');
}
```

### 🎛️ 动态并发控制

```dart
void main() async {
  final limit = fLimit(1);
  
  // 📝 从有限的并发开始
  final futures = <Future<String>>[];
  for (int i = 0; i < 10; i++) {
    futures.add(limit(() async {
      print('🔄 任务 $i（并发数：${limit.concurrency}）');
      await Future.delayed(Duration(milliseconds: 100));
      return '任务 $i 完成';
    }));
  }
  
  // 🚀 一段时间后增加并发数
  Future.delayed(Duration(milliseconds: 300), () {
    print('⬆️ 将并发数增加到 5');
    limit.concurrency = 5;
  });
  
  await Future.wait(futures);
  print('🎉 所有任务完成');
}
```

### 📋 队列策略

#### 🔄 FIFO（先进先出）- 默认策略

```dart
final limit = fLimit(2, queueStrategy: QueueStrategy.fifo);
// 任务按添加顺序执行
```

#### 📚 LIFO（后进先出）

```dart
final limit = fLimit(2, queueStrategy: QueueStrategy.lifo);
// 任务按倒序执行（栈式行为）
```

#### ⭐ 优先级队列

```dart
final limit = fLimit(2, queueStrategy: QueueStrategy.priority);

// 🎯 添加不同优先级的任务
limit(() async {
  print('🔵 后台任务');
}, priority: 1);

limit(() async {
  print('🔴 紧急任务');
}, priority: 10);

limit(() async {
  print('🟡 重要任务');
}, priority: 5);

// ⚡ 执行顺序：紧急任务 (10)，重要任务 (5)，后台任务 (1)
```

### 🏆 基于优先级的任务管理

```dart
void main() async {
  final limit = fLimit(1, queueStrategy: QueueStrategy.priority);
  
  final futures = <Future<void>>[];
  
  // 🟢 低优先级
  futures.add(limit(() async {
    print('🟢 后台维护');
  }, priority: 1));
  
  // 🟡 中等优先级
  futures.add(limit(() async {
    print('🟡 用户通知');
  }, priority: 5));
  
  // 🔴 高优先级
  futures.add(limit(() async {
    print('🔴 关键安全更新');
  }, priority: 10));
  
  await Future.wait(futures);
  // 输出：🔴 🟡 🟢
}
```

## 📖 API 参考

### 🔧 `fLimit(int concurrency, {QueueStrategy queueStrategy})`

创建并发限制器。

**参数：**

- `concurrency` - 最大并发操作数（≥ 1）
- `queueStrategy` - 队列执行策略（可选，默认为 FIFO）

**返回：** `FLimit` 实例

### 📊 `QueueStrategy`

队列执行策略：

| 策略 | 描述 | 使用场景 |
|----------|-------------|----------|
| `fifo` | 先进先出 | 📋 公平的任务执行 |
| `lifo` | 后进先出 | 📚 栈式处理 |
| `priority` | 基于优先级 | ⭐ 重要任务优先 |

### 🏗️ `FLimit` 类

#### 属性

- `activeCount` - 🔄 当前正在执行的操作数
- `pendingCount` - ⏳ 队列中的操作数
- `concurrency` - 🎛️ 当前并发限制（可读写）
- `queueStrategy` - 📋 当前队列策略

#### 方法

- `call(function, {priority})` - 🚀 使用并发限制执行函数
- `isolate(computation, {priority})` - 🧵 在单独的 isolate 中执行计算
- `map(items, mapper)` - 🗺️ 并发映射项目
- `onIdle` - 💤 等待空闲状态
- `clearQueue()` - 🗑️ 清空所有等待中的操作

### 🔗 `limitFunction<T>(function, options)`

创建函数的限制版本。

**参数：**

- `function` - 要限制的函数
- `options` - 包含并发和队列策略的 `LimitOptions`

**返回：** 限制版本的函数包装器

## 🛡️ 错误处理

限制器能够正确处理异步操作中的错误：

```dart
final limit = fLimit(2);

final future1 = limit(() async {
  throw Exception('💥 出现问题了');
});

final future2 = limit(() async {
  return '✅ 成功';
});

try {
  await future1; // 这里会抛出异常
} catch (e) {
  print('❌ 捕获错误：$e');
}

final result = await future2; // 这里会成功
print('✅ 结果：$result');
```

## 🧵 Isolate 支持 (Dart 2.19+)

你可以使用 `isolate` 在单独的 isolate 中运行计算密集型任务，同时遵守并发限制：

```dart
final limit = fLimit(2);

// ⚡ 这将在单独的 isolate 中运行！
final result = await limit.isolate(() {
  // 🔨 繁重的计算
  int sum = 0;
  for (int i = 0; i < 1000000; i++) {
    sum += i;
  }
  return sum;
});

print('Result: $result');
```

**注意：** 传递给 `isolate` 的函数必须是静态函数、顶层函数或 [可发送](https://api.dart.dev/stable/dart-isolate/Isolate/run.html) 的闭包（即不捕获任何不可发送的对象）。

## 🛠️ 扩展方法

### `map`

并发处理迭代器中的项目：

```dart
final limit = fLimit(2);
final items = [1, 2, 3, 4, 5];

// 使用并发限制映射项目到结果
final results = await limit.map(items, (item) async {
  await Future.delayed(Duration(seconds: 1));
  return item * 2;
});
```

### `onIdle`

等待所有任务完成：

```dart
await limit.onIdle;
print('所有任务已完成且队列为空');
```

## 🔍 监控和调试

```dart
final limit = fLimit(3);

// 📊 监控队列状态
print('活跃：${limit.activeCount}');
print('等待：${limit.pendingCount}');
print('策略：${limit.queueStrategy}');

// 🔧 添加任务并监控
for (int i = 0; i < 10; i++) {
  limit(() async {
    print('📊 活跃：${limit.activeCount}，等待：${limit.pendingCount}');
    await Future.delayed(Duration(milliseconds: 100));
  });
}
```

## 🆚 与 JavaScript p-limit 的对比

| JavaScript | Dart | 描述 |
|------------|------|-------------|
| `const limit = pLimit(2)` | `final limit = fLimit(2)` | 🔧 创建限制器 |
| `limit(() => asyncTask())` | `limit(() => asyncTask())` | 🚀 执行任务 |
| `limit.activeCount` | `limit.activeCount` | 📊 活跃数量 |
| `limit.pendingCount` | `limit.pendingCount` | ⏳ 等待数量 |
| `limit.clearQueue()` | `limit.clearQueue()` | 🗑️ 清空队列 |

## 🎯 高级示例

### 📁 基于优先级的文件处理

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
  
  // 🔴 关键系统文件
  limit(() => processFile('system.log'), priority: TaskPriority.high.value);
  
  // 🟡 用户文档
  limit(() => processFile('document.pdf'), priority: TaskPriority.medium.value);
  
  // 🟢 缓存文件
  limit(() => processFile('cache.tmp'), priority: TaskPriority.low.value);
}
```

### 🌊 批量处理

```dart
Future<void> batchProcess(List<String> items) async {
  final limit = fLimit(5);
  
  await Future.wait(
    items.map((item) => limit(() => processItem(item)))
  );
  
  print('🎉 批量处理完成！');
}
```

## 🤝 贡献

我们欢迎贡献！

## 📄 许可证

本项目采用 MIT 许可证 - 查看 [LICENSE](https://github.com/fluttercandies/f_limit/blob/main/LICENSE) 文件了解详情。

## 🙏 致谢

- 灵感来自 Sindre Sorhus 的 [p-limit](https://github.com/sindresorhus/p-limit)
- [FlutterCandies](https://github.com/fluttercandies) 组织的一部分

---

<div align="center">

**[🏠 FlutterCandies](https://github.com/fluttercandies) | [📦 pub.dev](https://pub.dev/packages/f_limit) | [🐛 Issues](https://github.com/fluttercandies/f_limit/issues)**

由 FlutterCandies 团队用 ❤️ 制作

</div>
