import 'package:f_limit/f_limit.dart';

void main() async {
  await basicUsageExample();
  await limitFunctionExample();
  await dynamicConcurrencyExample();
  await queueStrategyExamples();
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
  final futures = tasks.map((task) => limit(task));
  final results = await Future.wait(futures);

  print('All tasks completed: $results');
  print('');
}

/// Example using limitFunction
Future<void> limitFunctionExample() async {
  print('=== Limit Function Example ===');

  // Original function that fetches data
  Future<String> fetchData(String url) async {
    print('Fetching data from $url');
    await Future.delayed(Duration(milliseconds: 200));
    return 'Data from $url';
  }

  // Create a limited version with concurrency of 2
  final limitedFetch = limitFunction(
    () => fetchData('https://api.example.com'),
    LimitOptions(concurrency: 2),
  );

  // Execute multiple requests
  final futures = List.generate(4, (i) => limitedFetch());
  final results = await Future.wait(futures);

  print('Fetch results: $results');
  print('');
}

/// Example showing dynamic concurrency adjustment
Future<void> dynamicConcurrencyExample() async {
  print('=== Dynamic Concurrency Example ===');

  final limit = fLimit(1);

  // Start some tasks
  final futures = <Future<String>>[];
  for (int i = 0; i < 5; i++) {
    futures.add(limit(() async {
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

  await Future.wait(futures);
  print('All dynamic tasks completed');
  print('');
}

/// Examples demonstrating different queue strategies
Future<void> queueStrategyExamples() async {
  print('=== Queue Strategy Examples ===');

  await _demonstrateFIFO();
  await _demonstrateLIFO();
  await _demonstratePriority();
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
  await Future.delayed(Duration(milliseconds: 500));
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
  await Future.delayed(Duration(milliseconds: 500));
  print('LIFO demonstration completed\n');
}

/// Demonstrate Priority queue strategy
Future<void> _demonstratePriority() async {
  print('--- Priority Strategy (High Priority First) ---');

  final limit = fLimit(1, queueStrategy: QueueStrategy.priority);

  // Add tasks with different priorities
  final futures = <Future<void>>[];

  // Low priority tasks
  futures.add(limit(() async {
    print('Priority Task: Low priority (1)');
    await Future.delayed(Duration(milliseconds: 50));
  }, priority: 1));

  futures.add(limit(() async {
    print('Priority Task: Low priority (1)');
    await Future.delayed(Duration(milliseconds: 50));
  }, priority: 1));

  // High priority task (added later but should execute first)
  await Future.delayed(Duration(milliseconds: 20));
  futures.add(limit(() async {
    print('Priority Task: HIGH priority (10)');
    await Future.delayed(Duration(milliseconds: 50));
  }, priority: 10));

  // Medium priority task
  await Future.delayed(Duration(milliseconds: 20));
  futures.add(limit(() async {
    print('Priority Task: Medium priority (5)');
    await Future.delayed(Duration(milliseconds: 50));
  }, priority: 5));

  // Another high priority task
  await Future.delayed(Duration(milliseconds: 20));
  futures.add(limit(() async {
    print('Priority Task: HIGH priority (10)');
    await Future.delayed(Duration(milliseconds: 50));
  }, priority: 10));

  await Future.wait(futures);
  print('Priority demonstration completed\n');
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

  // Use the onIdle extension to wait for all tasks to complete
  print('Waiting for all tasks to complete...');
  await limit.onIdle;
  print('All tasks completed successfully');
  print('');
}

/// Example demonstrating FLimitIsolate
Future<void> isolateExample() async {
  print('=== FLimitIsolate Example ===');

  final limit = fLimit(2);

  // Simple computation to run in isolate
  int fibonacci(int n) {
    if (n <= 1) return n;
    return fibonacci(n - 1) + fibonacci(n - 2);
  }

  // Use isolate extension to run computation in separate isolate
  final futures = <Future<int>>[];
  for (int i = 30; i < 35; i++) {
    futures.add(limit.isolate(() async {
      print('Computing fibonacci($i) in isolate');
      final result = fibonacci(i);
      print('fibonacci($i) = $result');
      return result;
    }));
  }

  final results = await Future.wait(futures);
  print('Fibonacci results: $results');
  
  // Wait for all isolate tasks to complete
  await limit.onIdle;
  print('All isolate computations completed');
  print('');
}
