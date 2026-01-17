# 🚦 f_limit

[![pub package](https://img.shields.io/pub/v/f_limit.svg)](https://pub.dev/packages/f_limit)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)

Dart 异步并发限制器。

**中文文档** | **[English](README.md)**

---

## 📦 安装

```yaml
dependencies:
  f_limit: ^1.0.0
```

```bash
dart pub get
```

---

## ⚡ 快速开始

```dart
import 'package:f_limit/f_limit.dart';

void main() async {
  final limit = fLimit(2); // 最多 2 个并发操作

  final tasks = List.generate(5, (i) => () async {
    await Future.delayed(Duration(seconds: 1));
    return i;
  });

  final results = await Future.wait(tasks.map((task) => limit(task)));
  print('完成: $results');
}
```

---

## 📋 队列策略

| 策略 | 描述 | 适用场景 |
|------|------|----------|
| `fifo` | 先进先出 | 默认，公平执行 |
| `lifo` | 后进先出 | 栈式，最新优先 |
| `priority` | 优先级 | 重要任务优先 |
| `alternating` | 头→尾→头... | 双向公平调度 |
| `random` | 随机选择 | 负载均衡 |

```dart
final limit = fLimit(2, queueStrategy: QueueStrategy.priority);
```

---

## 📖 API

### 构造函数

| 方法 | 描述 |
|------|------|
| `fLimit(concurrency, {queueStrategy})` | 创建限制器 |

### 属性

| 属性 | 类型 | 描述 |
|------|------|------|
| `activeCount` | `int` | 正在执行数 |
| `pendingCount` | `int` | 队列等待数 |
| `concurrency` | `int` | 最大并发（可读写） |
| `queueStrategy` | `QueueStrategy` | 当前策略 |

### 方法

| 方法 | 描述 |
|------|------|
| `call(fn, {priority})` | 执行并限制并发 |
| `clearQueue()` | 清空队列 |
| `isolate(fn, {priority})` | 在 isolate 中执行 |
| `map(items, mapper)` | 并发映射 |
| `onIdle` | 等待全部完成 |

---

## 🎯 示例

### 优先级队列

```dart
final limit = fLimit(1, queueStrategy: QueueStrategy.priority);

limit(() => print('🔴 紧急'), priority: 10);
limit(() => print('🟡 普通'), priority: 5);
limit(() => print('🟢 后台'), priority: 1);

// 输出: 🔴 🟡 🟢
```

### 动态并发

```dart
final limit = fLimit(1);

limit.concurrency = 5; // 运行时增加
print('最大并发: ${limit.concurrency}');
```

### 清空队列

```dart
final limit = fLimit(1);

// 添加大量任务...
for (int i = 0; i < 100; i++) {
  limit(() async => i);
}

print('等待: ${limit.pendingCount}'); // 99
limit.clearQueue();
print('等待: ${limit.pendingCount}'); // 0
```

---

## 📄 许可证

MIT © [FlutterCandies](https://github.com/fluttercandies)
