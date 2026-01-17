import 'package:f_limit/f_limit.dart';
import 'package:test/test.dart';

void main() {
  group('FLimit', () {
    test('should limit concurrency', () async {
      final limit = fLimit(2);
      int activeCount = 0;
      int maxActiveCount = 0;

      final tasks = List.generate(
          5,
          (i) => () async {
                activeCount++;
                maxActiveCount =
                    maxActiveCount > activeCount ? maxActiveCount : activeCount;
                await Future.delayed(Duration(milliseconds: 10));
                activeCount--;
                return i;
              });

      final futures = tasks.map((task) => limit(task));
      final results = await Future.wait(futures);

      expect(results, equals([0, 1, 2, 3, 4]));
      expect(maxActiveCount, equals(2));
    });

    test('should track active and pending counts', () async {
      final limit = fLimit(1);

      expect(limit.activeCount, equals(0));
      expect(limit.pendingCount, equals(0));

      final future1 = limit(() async {
        await Future.delayed(Duration(milliseconds: 50));
        return 'task1';
      });

      final future2 = limit(() async {
        await Future.delayed(Duration(milliseconds: 50));
        return 'task2';
      });

      // Give time for tasks to be queued
      await Future.delayed(Duration(milliseconds: 10));

      expect(limit.activeCount, equals(1));
      expect(limit.pendingCount, equals(1));

      await Future.wait([future1, future2]);

      expect(limit.activeCount, equals(0));
      expect(limit.pendingCount, equals(0));
    });

    test('should allow changing concurrency', () async {
      final limit = fLimit(1);

      expect(limit.concurrency, equals(1));

      limit.concurrency = 3;
      expect(limit.concurrency, equals(3));

      // Test that changing concurrency processes more tasks
      int activeCount = 0;
      int maxActiveCount = 0;

      final tasks = List.generate(
          4,
          (i) => () async {
                activeCount++;
                maxActiveCount =
                    maxActiveCount > activeCount ? maxActiveCount : activeCount;
                await Future.delayed(Duration(milliseconds: 20));
                activeCount--;
                return i;
              });

      final futures = tasks.map((task) => limit(task));
      await Future.wait(futures);

      expect(maxActiveCount, equals(3));
    });

    test('should clear queue', () async {
      final limit = fLimit(1);

      // Start a long-running task
      final future1 = limit(() async {
        await Future.delayed(Duration(milliseconds: 100));
        return 'task1';
      });

      // Queue more tasks (we don't need to store them since they'll be cleared)
      limit(() async => 'task2');
      limit(() async => 'task3');

      // Give time for tasks to be queued
      await Future.delayed(Duration(milliseconds: 10));

      expect(limit.pendingCount, equals(2));

      limit.clearQueue();

      expect(limit.pendingCount, equals(0));

      // First task should still complete
      final result1 = await future1;
      expect(result1, equals('task1'));

      // Other tasks were cleared from the queue
    });

    test('should handle errors', () async {
      final limit = fLimit(2);

      final future1 = limit(() async {
        await Future.delayed(Duration(milliseconds: 10));
        throw Exception('Test error');
      });

      final future2 = limit(() async {
        await Future.delayed(Duration(milliseconds: 10));
        return 'success';
      });

      expect(future1, throwsException);
      expect(await future2, equals('success'));
    });

    test('should validate concurrency', () {
      expect(() => fLimit(0), throwsArgumentError);
      expect(() => fLimit(-1), throwsArgumentError);

      final limit = fLimit(1);
      expect(() => limit.concurrency = 0, throwsArgumentError);
      expect(() => limit.concurrency = -1, throwsArgumentError);
    });
  });

  group('limitFunction', () {
    test('should create a limited function', () async {
      int callCount = 0;

      Future<String> originalFunction() async {
        callCount++;
        await Future.delayed(Duration(milliseconds: 10));
        return 'result $callCount';
      }

      final limitedFunction = limitFunction(
        originalFunction,
        LimitOptions(concurrency: 1),
      );

      final futures = List.generate(3, (_) => limitedFunction());
      final results = await Future.wait(futures);

      expect(results, hasLength(3));
      expect(callCount, equals(3));
    });
  });

  group('Queue Strategies', () {
    test('FIFO strategy should execute tasks in order', () async {
      final limit = fLimit(1, queueStrategy: QueueStrategy.fifo);
      final executionOrder = <int>[];

      // Add tasks that record their execution order
      final futures = <Future<void>>[];
      for (int i = 0; i < 5; i++) {
        futures.add(limit(() async {
          executionOrder.add(i);
          await Future.delayed(Duration(milliseconds: 10));
        }));
      }

      await Future.wait(futures);
      expect(executionOrder, equals([0, 1, 2, 3, 4]));
    });

    test('LIFO strategy should execute tasks in reverse order', () async {
      final limit = fLimit(1, queueStrategy: QueueStrategy.lifo);
      final executionOrder = <int>[];

      // Add tasks that record their execution order
      // Note: First task will execute immediately, others will be queued
      final futures = <Future<void>>[];
      for (int i = 0; i < 5; i++) {
        futures.add(limit(() async {
          executionOrder.add(i);
          await Future.delayed(Duration(milliseconds: 10));
        }));
        // Small delay to ensure queueing order
        if (i == 0) await Future.delayed(Duration(milliseconds: 20));
      }

      await Future.wait(futures);
      // First task executes immediately, then LIFO order for the rest
      expect(executionOrder, equals([0, 4, 3, 2, 1]));
    });

    test('Priority strategy should execute high priority tasks first',
        () async {
      final limit = fLimit(1, queueStrategy: QueueStrategy.priority);
      final executionOrder = <String>[];

      // Start with a blocking task
      final futures = <Future<void>>[];
      futures.add(limit(() async {
        executionOrder.add('blocking');
        await Future.delayed(Duration(milliseconds: 30));
      }));

      // Add tasks with different priorities while blocking task is running
      await Future.delayed(Duration(milliseconds: 10));

      futures.add(limit(() async {
        executionOrder.add('low-1');
        await Future.delayed(Duration(milliseconds: 5));
      }, priority: 1));

      futures.add(limit(() async {
        executionOrder.add('high-10');
        await Future.delayed(Duration(milliseconds: 5));
      }, priority: 10));

      futures.add(limit(() async {
        executionOrder.add('medium-5');
        await Future.delayed(Duration(milliseconds: 5));
      }, priority: 5));

      futures.add(limit(() async {
        executionOrder.add('high-10-2');
        await Future.delayed(Duration(milliseconds: 5));
      }, priority: 10));

      await Future.wait(futures);

      // Should be: blocking, then high priority tasks, then medium, then low
      expect(
          executionOrder,
          equals([
            'blocking',
            'high-10', // First high priority task
            'high-10-2', // Second high priority task (same priority, FIFO within priority)
            'medium-5', // Medium priority
            'low-1' // Low priority
          ]));
    });

    test('should support priority in limitFunction', () async {
      final executionOrder = <String>[];

      Future<void> taskA() async {
        executionOrder.add('A');
        await Future.delayed(Duration(milliseconds: 5));
      }

      Future<void> taskB() async {
        executionOrder.add('B');
        await Future.delayed(Duration(milliseconds: 5));
      }

      final limitedA = limitFunction(
        taskA,
        LimitOptions(concurrency: 1, queueStrategy: QueueStrategy.priority),
      );

      final limit = fLimit(1, queueStrategy: QueueStrategy.priority);

      // Start blocking task
      final futures = <Future<void>>[];
      futures.add(limit(() async {
        executionOrder.add('blocking');
        await Future.delayed(Duration(milliseconds: 20));
      }));

      // Queue tasks with different priorities
      await Future.delayed(Duration(milliseconds: 5));
      futures.add(limit(() => taskB(), priority: 1)); // Low priority
      futures.add(limitedA()); // Default priority (0)
      futures.add(limit(() => taskA(), priority: 10)); // High priority

      await Future.wait(futures);

      expect(executionOrder, equals(['blocking', 'A', 'A', 'B']));
    });

    test('Alternating strategy should execute tasks from head and tail alternately',
        () async {
      final executionOrder = <int>[];

      // Create all task functions first (don't execute yet)
      final tasks = List.generate(
          5,
          (i) => () async {
                executionOrder.add(i);
                await Future.delayed(Duration(milliseconds: 5));
              });

      // Use concurrency of 1 and alternating strategy
      final limit = fLimit(1, queueStrategy: QueueStrategy.alternating);

      // Queue all tasks quickly without waiting
      final futures = tasks.map((task) => limit(task)).toList();

      await Future.wait(futures);

      // Queue: [0, 1, 2, 3, 4]
      // Alternating: head(0), tail(4), head(1), tail(3), head(2)
      expect(executionOrder, equals([0, 4, 1, 3, 2]));
    });

    test('Random strategy should execute tasks in random order', () async {
      final executionOrder = <int>[];

      // Create all task functions first (don't execute yet)
      final tasks = List.generate(
          10,
          (i) => () async {
                executionOrder.add(i);
                await Future.delayed(Duration(milliseconds: 2));
              });

      // Use concurrency of 1 and random strategy
      final limit = fLimit(1, queueStrategy: QueueStrategy.random);

      // Queue all tasks quickly without waiting
      final futures = tasks.map((task) => limit(task)).toList();

      await Future.wait(futures);

      // All tasks should be executed
      expect(executionOrder, hasLength(10));
      expect(executionOrder.toSet(), equals({0, 1, 2, 3, 4, 5, 6, 7, 8, 9}));

      // Random order should NOT be sequential (very unlikely to be 0,1,2,3,4,5,6,7,8,9)
      expect(executionOrder, isNot(equals([0, 1, 2, 3, 4, 5, 6, 7, 8, 9])));
    });

    test('should track queue strategy', () {
      final fifoLimit = fLimit(2, queueStrategy: QueueStrategy.fifo);
      final lifoLimit = fLimit(2, queueStrategy: QueueStrategy.lifo);
      final priorityLimit = fLimit(2, queueStrategy: QueueStrategy.priority);
      final alternatingLimit =
          fLimit(2, queueStrategy: QueueStrategy.alternating);
      final randomLimit = fLimit(2, queueStrategy: QueueStrategy.random);

      expect(fifoLimit.queueStrategy, equals(QueueStrategy.fifo));
      expect(lifoLimit.queueStrategy, equals(QueueStrategy.lifo));
      expect(priorityLimit.queueStrategy, equals(QueueStrategy.priority));
      expect(alternatingLimit.queueStrategy, equals(QueueStrategy.alternating));
      expect(randomLimit.queueStrategy, equals(QueueStrategy.random));
    });
  });
}
