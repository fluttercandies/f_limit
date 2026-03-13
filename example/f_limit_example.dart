import 'package:f_limit/f_limit.dart';

void main() async {
  await basicUsageExample();
  await taskHandleExample();
  await dynamicConcurrencyExample();
  await queueStrategyExamples();
  await timeoutExample();
  await retryExample();
  await pauseResumeExample();
  await extensionsExample();
  await isolateExample();
}

/// Basic usage example
Future<void> basicUsageExample() async {
  print('=== Basic Usage Example ===');

  // Create a limiter that allows only 2 concurrent operations
  final limit = fLimit(2);

  // Create some async tasks
  final tasks = List.generate(
      5,
      (i) => () async {
            print(
                'Task $i started (active: ${limit.activeCount}, pending: ${limit.pendingCount})');
            await Future.delayed(Duration(milliseconds: 100 * (i + 1)));
            print('Task $i completed');
            return 'Result $i';
          });

  // Execute all tasks with concurrency limit
  final handles = tasks.map((task) => limit(task));
  final results = await Future.wait(handles);

  print('All tasks completed: $results');
  print('');
}

/// Example demonstrating TaskHandle features
Future<void> taskHandleExample() async {
  print('=== TaskHandle Example ===');

  final limit = fLimit(1);

  // Block the limiter with a long task
  limit(() async {
    await Future.delayed(Duration(milliseconds: 500));
  });

  // Add another task that we can control
  final handle = limit(() async {
    print('Controlled task executed');
    return 'controlled result';
  });

  print('Task ID: ${handle.id}');
  print('Is started: ${handle.isStarted}');
  print('Is completed: ${handle.isCompleted}');
  print('Is canceled: ${handle.isCanceled}');

  // Try to cancel if not started
  if (!handle.isStarted) {
    final canceled = handle.cancel();
    print('Cancel attempt: $canceled');
  }

  // Wait for result (or handle cancellation)
  try {
    final result = await handle;
    print('Result: $result');
  } on CanceledException {
    print('Task was canceled');
  }

  await limit.onIdle;
  print('');
}

/// Example showing dynamic concurrency adjustment
Future<void> dynamicConcurrencyExample() async {
  print('=== Dynamic Concurrency Example ===');

  final limit = fLimit(1);

  // Start some tasks
  final handles = <TaskHandle<String>>[];
  for (int i = 0; i < 5; i++) {
    handles.add(limit(() async {
      print('Task $i started (concurrency: ${limit.concurrency})');
      await Future.delayed(Duration(milliseconds: 100));
      print('Task $i completed');
      return 'Task $i done';
    }));
  }

  // After a short delay, increase concurrency
  Future.delayed(Duration(milliseconds: 150), () {
    print('Increasing concurrency to 3');
    limit.concurrency = 3;
  });

  await Future.wait(handles);
  print('All dynamic tasks completed');
  print('');
}

/// Examples demonstrating different queue strategies
Future<void> queueStrategyExamples() async {
  print('=== Queue Strategy Examples ===');

  await _demonstrateFIFO();
  await _demonstrateLIFO();
  await _demonstratePriority();
  await _demonstrateAlternating();
  await _demonstrateRandom();
}

/// Demonstrate FIFO (First In, First Out) queue strategy
Future<void> _demonstrateFIFO() async {
  print('--- FIFO Strategy (First In, First Out) ---');

  final limit = fLimit(1, queueStrategy: QueueStrategy.fifo);

  // Add tasks with delays to see the order
  for (int i = 0; i < 5; i++) {
    limit(() async {
      print('FIFO Task $i executed');
      await Future.delayed(Duration(milliseconds: 50));
    });
    // Small delay to ensure order
    await Future.delayed(Duration(milliseconds: 10));
  }

  // Wait for completion
  await limit.onIdle;
  print('FIFO demonstration completed\n');
}

/// Demonstrate LIFO (Last In, First Out) queue strategy
Future<void> _demonstrateLIFO() async {
  print('--- LIFO Strategy (Last In, First Out) ---');

  final limit = fLimit(1, queueStrategy: QueueStrategy.lifo);

  // Add tasks with delays to see the reverse order
  for (int i = 0; i < 5; i++) {
    limit(() async {
      print('LIFO Task $i executed');
      await Future.delayed(Duration(milliseconds: 50));
    });
    // Small delay to ensure order
    await Future.delayed(Duration(milliseconds: 10));
  }

  // Wait for completion
  await limit.onIdle;
  print('LIFO demonstration completed\n');
}

/// Demonstrate Priority queue strategy
Future<void> _demonstratePriority() async {
  print('--- Priority Strategy (High Priority First) ---');

  final limit = fLimit(1, queueStrategy: QueueStrategy.priority);

  // Add tasks with different priorities
  final handles = <TaskHandle<void>>[];

  // Low priority tasks
  handles.add(limit(() async {
    print('Priority Task: Low priority (1)');
    await Future.delayed(Duration(milliseconds: 50));
  }, priority: 1));

  handles.add(limit(() async {
    print('Priority Task: Low priority (1)');
    await Future.delayed(Duration(milliseconds: 50));
  }, priority: 1));

  // High priority task (added later but should execute first)
  await Future.delayed(Duration(milliseconds: 20));
  handles.add(limit(() async {
    print('Priority Task: HIGH priority (10)');
    await Future.delayed(Duration(milliseconds: 50));
  }, priority: 10));

  // Medium priority task
  await Future.delayed(Duration(milliseconds: 20));
  handles.add(limit(() async {
    print('Priority Task: Medium priority (5)');
    await Future.delayed(Duration(milliseconds: 50));
  }, priority: 5));

  // Another high priority task
  await Future.delayed(Duration(milliseconds: 20));
  handles.add(limit(() async {
    print('Priority Task: HIGH priority (10)');
    await Future.delayed(Duration(milliseconds: 50));
  }, priority: 10));

  await Future.wait(handles);
  print('Priority demonstration completed\n');
}

/// Demonstrate Alternating queue strategy
Future<void> _demonstrateAlternating() async {
  print('--- Alternating Strategy (Head -> Tail -> Head...) ---');

  final limit = fLimit(1, queueStrategy: QueueStrategy.alternating);

  for (int i = 0; i < 5; i++) {
    limit(() async {
      print('Alternating Task $i executed');
      await Future.delayed(Duration(milliseconds: 30));
    });
    await Future.delayed(Duration(milliseconds: 10));
  }

  await limit.onIdle;
  print('Alternating demonstration completed\n');
}

/// Demonstrate Random queue strategy
Future<void> _demonstrateRandom() async {
  print('--- Random Strategy (Random Selection) ---');

  final limit = fLimit(1, queueStrategy: QueueStrategy.random);

  for (int i = 0; i < 5; i++) {
    limit(() async {
      print('Random Task $i executed');
      await Future.delayed(Duration(milliseconds: 30));
    });
  }

  await limit.onIdle;
  print('Random demonstration completed\n');
}

/// Example demonstrating timeout feature
Future<void> timeoutExample() async {
  print('=== Timeout Example ===');

  final limit = fLimit(2);

  // Task that will timeout
  final handle = limit(
    () async {
      print('Starting slow task...');
      await Future.delayed(Duration(seconds: 10));
      return 'This will never be returned';
    },
    timeout: Duration(milliseconds: 100),
  );

  try {
    await handle;
  } on TimeoutException catch (e) {
    print('Task timed out as expected: ${e.message}');
  }

  print('');
}

/// Example demonstrating retry policies
Future<void> retryExample() async {
  print('=== Retry Example ===');

  final limit = fLimit(1);
  int attempts = 0;

  // Task with simple retry
  final handle1 = limit(
    () async {
      attempts++;
      print('Attempt $attempts');
      if (attempts < 3) {
        throw Exception('Simulated failure');
      }
      return 'Success on attempt $attempts';
    },
    retry: RetrySimple(maxAttempts: 5),
  );

  final result1 = await handle1;
  print('Result: $result1');

  // Task with exponential backoff
  int apiAttempts = 0;
  final handle2 = limit(
    () async {
      apiAttempts++;
      print('API attempt $apiAttempts');
      if (apiAttempts < 3) {
        throw Exception('API temporarily unavailable');
      }
      return 'API success';
    },
    retry: RetryExponential(
      maxAttempts: 5,
      baseDelay: Duration(milliseconds: 50),
      multiplier: 2.0,
    ),
  );

  final result2 = await handle2;
  print('API Result: $result2');

  print('');
}

/// Example demonstrating pause and resume
Future<void> pauseResumeExample() async {
  print('=== Pause and Resume Example ===');

  final limit = fLimit(2);
  final executed = <int>[];

  // Add tasks
  for (int i = 0; i < 10; i++) {
    limit(() async {
      executed.add(i);
      print('Task $i started');
      await Future.delayed(Duration(milliseconds: 80));
      print('Task $i completed');
    });
  }

  // Pause after a short delay
  await Future.delayed(Duration(milliseconds: 20));
  print('Pausing limiter...');
  limit.pause();
  print('Is paused: ${limit.isPaused}');
  print('Tasks started so far: ${executed.length}');

  // Wait a bit - no new tasks should execute
  await Future.delayed(Duration(milliseconds: 120));
  print('Tasks started after pause window: ${executed.length}');

  // Resume
  print('Resuming limiter...');
  limit.resume();
  print('Is paused: ${limit.isPaused}');

  // Wait for all tasks
  await limit.onIdle;
  print('All tasks started: ${executed.length}');

  print('');
}

/// Example demonstrating FLimitExtensions
Future<void> extensionsExample() async {
  print('=== FLimitExtensions Example ===');

  final limit = fLimit(2);

  // Use the map extension to process items
  final items = [1, 2, 3, 4, 5];
  final results = await limit.map(items, (item) async {
    print('Processing item $item');
    await Future.delayed(Duration(milliseconds: 100));
    return item * 2;
  });

  print('Map results: $results');

  // Use filter extension
  final evens = await limit.filter(items, (item) async {
    return item % 2 == 0;
  });
  print('Filter (even): $evens');

  // Use forEach extension
  await limit.forEach(items, (item) async {
    print('forEach: processing $item');
  });

  // Use mapIndexed extension
  final indexed = await limit.mapIndexed(items, (index, item) async {
    return 'Index $index: $item';
  });
  print('mapIndexed: $indexed');

  // Use reduce extension
  final sum = await limit.reduce(items, (a, b) async => a + b);
  print('Reduce (sum): $sum');

  // Wait for idle
  print('Waiting for all tasks to complete...');
  await limit.onIdle;
  print('All tasks completed successfully');
  print('');
}

/// Top-level function for isolate (must be top-level for sendable)
int _fibonacci(int n) {
  if (n <= 1) return n;
  return _fibonacci(n - 1) + _fibonacci(n - 2);
}

/// Example demonstrating FLimitIsolate
Future<void> isolateExample() async {
  print('=== FLimitIsolate Example ===');

  final limit = fLimit(2);

  // Use isolate extension to run computation in separate isolate
  final handles = <TaskHandle<int>>[];
  for (int i = 30; i < 35; i++) {
    handles.add(limit.isolate(() {
      print('Computing fibonacci($i) in isolate');
      final result = _fibonacci(i);
      print('fibonacci($i) = $result');
      return result;
    }));
  }

  final results = await Future.wait(handles);
  print('Fibonacci results: $results');

  // Wait for all isolate tasks to complete
  await limit.onIdle;
  print('All isolate computations completed');
  print('');
}
