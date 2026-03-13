/// Performance benchmarks for f_limit
///
/// Run with: dart run benchmark/f_limit_benchmark.dart
library f_limit.benchmark;

import 'package:f_limit/f_limit.dart';

void main() async {
  print('🚀 f_limit Performance Benchmarks\n');
  print('=' * 50);

  await benchmarkConcurrency();
  await benchmarkQueueStrategies();
  await benchmarkLargeQueue();
  await benchmarkOnIdle();
  await benchmarkTaskHandle();

  print('\n${'=' * 50}');
  print('✅ All benchmarks completed!');
}

Future<void> benchmarkConcurrency() async {
  print('\n📊 Concurrency Benchmark');

  for (final concurrency in [1, 2, 4, 8, 16]) {
    final limit = fLimit(concurrency);
    final taskCount = 1000;
    final stopwatch = Stopwatch()..start();

    final handles = List.generate(taskCount, (i) {
      return limit(() async {
        // Simulate minimal async work
        await Future.delayed(Duration.zero);
        return i;
      });
    });

    await Future.wait(handles.map((h) => h.future));
    stopwatch.stop();

    final tasksPerMs = taskCount / stopwatch.elapsedMilliseconds;
    print('  Concurrency $concurrency: ${stopwatch.elapsedMilliseconds}ms '
        '($tasksPerMs tasks/ms)');
  }
}

Future<void> benchmarkQueueStrategies() async {
  print('\n📊 Queue Strategies Benchmark');

  final strategies = [
    QueueStrategy.fifo,
    QueueStrategy.lifo,
    QueueStrategy.priority,
    QueueStrategy.alternating,
    QueueStrategy.random,
  ];

  final taskCount = 500;

  for (final strategy in strategies) {
    final limit = fLimit(1, queueStrategy: strategy);
    final stopwatch = Stopwatch()..start();

    final handles = List.generate(taskCount, (i) {
      return limit(() async {
        await Future.delayed(Duration.zero);
        return i;
      }, priority: i % 10);
    });

    await Future.wait(handles.map((h) => h.future));
    stopwatch.stop();

    print(
        '  ${strategy.name.padRight(12)}: ${stopwatch.elapsedMilliseconds}ms');
  }
}

Future<void> benchmarkLargeQueue() async {
  print('\n📊 Large Queue Benchmark');

  final sizes = [1000, 5000, 10000];

  for (final size in sizes) {
    final limit = fLimit(4);
    final stopwatch = Stopwatch()..start();

    final handles = List.generate(size, (i) {
      return limit(() async {
        await Future.delayed(Duration.zero);
        return i;
      });
    });

    await Future.wait(handles.map((h) => h.future));
    stopwatch.stop();

    print('  $size tasks: ${stopwatch.elapsedMilliseconds}ms');
  }
}

Future<void> benchmarkOnIdle() async {
  print('\n📊 onIdle Benchmark');

  final limit = fLimit(4);
  final taskCount = 100;

  // Add tasks
  for (int i = 0; i < taskCount; i++) {
    limit(() async {
      await Future.delayed(Duration(milliseconds: 1));
    });
  }

  final stopwatch = Stopwatch()..start();
  await limit.onIdle;
  stopwatch.stop();

  print('  Waiting for $taskCount tasks: ${stopwatch.elapsedMilliseconds}ms');
}

Future<void> benchmarkTaskHandle() async {
  print('\n📊 TaskHandle Benchmark');

  final limit = fLimit(4);
  final taskCount = 1000;

  // Benchmark handle creation and cancellation
  final stopwatch1 = Stopwatch()..start();

  final handles = List.generate(taskCount, (i) {
    return limit(() async {
      await Future.delayed(Duration(milliseconds: 20));
      return i;
    });
  });

  // Cancel half the tasks
  for (int i = 0; i < taskCount ~/ 2; i++) {
    handles[i].cancel();
  }

  stopwatch1.stop();
  print(
      '  Creating & canceling ${taskCount ~/ 2} tasks: ${stopwatch1.elapsedMicroseconds}μs');

  // Clear remaining queue
  limit.clearQueue();

  await Future.wait(
    handles.map(
      (handle) => handle.then<void>((_) {}, onError: (_) {}),
    ),
  );

  // Benchmark handle future access
  final stopwatch2 = Stopwatch()..start();

  final handles2 = List.generate(taskCount, (i) {
    return limit(() async => i);
  });

  await Future.wait(handles2.map((h) => h.future));
  stopwatch2.stop();

  print(
      '  Future access for $taskCount tasks: ${stopwatch2.elapsedMilliseconds}ms');
}
