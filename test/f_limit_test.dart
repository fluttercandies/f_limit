import 'dart:async';

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

      final handles = tasks.map((task) => limit(task));
      final results = await Future.wait(handles);

      expect(results, equals([0, 1, 2, 3, 4]));
      expect(maxActiveCount, equals(2));
    });

    test('should track active and pending counts', () async {
      final limit = fLimit(1);

      expect(limit.activeCount, equals(0));
      expect(limit.pendingCount, equals(0));

      final handle1 = limit(() async {
        await Future.delayed(Duration(milliseconds: 50));
        return 'task1';
      });

      final handle2 = limit(() async {
        await Future.delayed(Duration(milliseconds: 50));
        return 'task2';
      });

      // Give time for tasks to be queued
      await Future.delayed(Duration(milliseconds: 10));

      expect(limit.activeCount, equals(1));
      expect(limit.pendingCount, equals(1));

      await Future.wait([handle1, handle2]);

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

      final handles = tasks.map((task) => limit(task));
      await Future.wait(handles);

      expect(maxActiveCount, equals(3));
    });

    test('should clear queue', () async {
      final limit = fLimit(1);

      // Start a long-running task
      final handle1 = limit(() async {
        await Future.delayed(Duration(milliseconds: 100));
        return 'task1';
      });

      // Queue more tasks and verify they are canceled when the queue is cleared
      final handle2 = limit(() async => 'task2');
      final handle3 = limit(() async => 'task3');

      // Give time for tasks to be queued
      await Future.delayed(Duration(milliseconds: 10));

      expect(limit.pendingCount, equals(2));

      final canceledTask2 =
          expectLater(handle2, throwsA(isA<CanceledException>()));
      final canceledTask3 =
          expectLater(handle3, throwsA(isA<CanceledException>()));

      expect(limit.clearQueue(), equals(2));

      expect(limit.pendingCount, equals(0));

      // First task should still complete
      final result1 = await handle1;
      expect(result1, equals('task1'));

      await canceledTask2;
      await canceledTask3;
    });

    test('should handle errors', () async {
      final limit = fLimit(2);

      final handle1 = limit(() async {
        await Future.delayed(Duration(milliseconds: 10));
        throw Exception('Test error');
      });

      final handle2 = limit(() async {
        await Future.delayed(Duration(milliseconds: 10));
        return 'success';
      });

      expect(handle1, throwsException);
      expect(await handle2, equals('success'));
    });

    test('should validate concurrency', () {
      expect(() => fLimit(0), throwsArgumentError);
      expect(() => fLimit(-1), throwsArgumentError);

      final limit = fLimit(1);
      expect(() => limit.concurrency = 0, throwsArgumentError);
      expect(() => limit.concurrency = -1, throwsArgumentError);
    });
  });

  group('TaskHandle', () {
    test('should return TaskHandle from call', () async {
      final limit = fLimit(2);
      final handle = limit(() async => 42);

      expect(handle, isA<TaskHandle<int>>());
      expect(handle.isCompleted, isFalse);

      final result = await handle;
      expect(result, equals(42));
      expect(handle.isCompleted, isTrue);
    });

    test('should be awaitable like Future', () async {
      final limit = fLimit(2);
      final handle = limit(() async => 42);

      final result = await handle;

      expect(result, equals(42));
      expect(handle.isCompleted, isTrue);
    });

    test('should be assignable to Future and work with Future.wait', () async {
      final limit = fLimit(2);

      final Future<int> future1 = limit(() async => 1);
      final Future<int> future2 = limit(() async => 2);
      final results = await Future.wait([future1, future2]);

      expect(results, equals([1, 2]));
    });

    test('should cancel pending task', () async {
      final limit = fLimit(1);

      // Start a blocking task
      limit(() async {
        await Future.delayed(Duration(milliseconds: 100));
      });

      // Queue a task that can be canceled
      final handle = limit(() async => 'should be canceled');

      await Future.delayed(Duration(milliseconds: 10));

      // Task is pending, should be cancelable
      expect(handle.isCanceled, isFalse);
      expect(handle.isStarted, isFalse);

      final canceled = handle.cancel();
      expect(canceled, isTrue);
      expect(handle.isCanceled, isTrue);

      // Future should complete with CanceledException
      expect(handle, throwsA(isA<CanceledException>()));
    });

    test('should not cancel started task', () async {
      final limit = fLimit(1);

      final handle = limit(() async {
        await Future.delayed(Duration(milliseconds: 50));
        return 'completed';
      });

      // Wait a bit for task to start
      await Future.delayed(Duration(milliseconds: 10));

      // Task is running, should not be cancelable
      final canceled = handle.cancel();
      expect(canceled, isFalse);

      final result = await handle;
      expect(result, equals('completed'));
    });

    test('should provide unique task IDs', () {
      final limit = fLimit(2);

      final handle1 = limit(() async => 1);
      final handle2 = limit(() async => 2);
      final handle3 = limit(() async => 3);

      expect(handle1.id, isNot(equals(handle2.id)));
      expect(handle2.id, isNot(equals(handle3.id)));
      expect(handle1.id, isNot(equals(handle3.id)));
    });

    test('should expose status transitions', () async {
      final limit = fLimit(1);
      final started = Completer<void>();
      final release = Completer<void>();

      final handle = limit(() async {
        started.complete();
        await release.future;
        return 42;
      });

      expect(handle.status, equals(TaskStatus.pending));

      await started.future;
      expect(handle.status, equals(TaskStatus.running));

      release.complete();
      expect(await handle, equals(42));
      expect(handle.status, equals(TaskStatus.completed));
    });
  });

  group('Pause and Resume', () {
    test('should pause and resume', () async {
      final limit = fLimit(2);
      final executionOrder = <int>[];

      expect(limit.isPaused, isFalse);

      // Pause before adding tasks
      limit.pause();
      expect(limit.isPaused, isTrue);

      // Add tasks - they should queue but not execute
      final handles = List.generate(3, (i) {
        return limit(() async {
          executionOrder.add(i);
          await Future.delayed(Duration(milliseconds: 10));
          return i;
        });
      });

      await Future.delayed(Duration(milliseconds: 50));

      // Tasks should not have started
      expect(executionOrder, isEmpty);

      // Resume
      limit.resume();
      expect(limit.isPaused, isFalse);

      await Future.wait(handles);

      // Now tasks should have executed
      expect(executionOrder, isNotEmpty);
    });

    test('should handle multiple pause/resume calls', () {
      final limit = fLimit(2);

      limit.pause();
      expect(limit.isPaused, isTrue);

      limit.pause(); // Double pause should be idempotent
      expect(limit.isPaused, isTrue);

      limit.resume();
      expect(limit.isPaused, isFalse);

      limit.resume(); // Double resume should be idempotent
      expect(limit.isPaused, isFalse);
    });
  });

  group('isEmpty and isBusy', () {
    test('should report isEmpty correctly', () async {
      final limit = fLimit(1);

      expect(limit.isEmpty, isTrue);
      expect(limit.isBusy, isFalse);

      final handle = limit(() async {
        await Future.delayed(Duration(milliseconds: 50));
      });

      await Future.delayed(Duration(milliseconds: 10));

      expect(limit.isEmpty, isFalse);
      expect(limit.isBusy, isTrue);

      await handle;

      expect(limit.isEmpty, isTrue);
      expect(limit.isBusy, isFalse);
    });
  });

  group('Timeout', () {
    test('should timeout long-running tasks', () async {
      final limit = fLimit(1);

      final handle = limit(
        () async {
          await Future.delayed(Duration(seconds: 10));
          return 'never reached';
        },
        timeout: Duration(milliseconds: 50),
      );

      expect(handle, throwsA(isA<TimeoutException>()));
    });

    test('should complete fast tasks within timeout', () async {
      final limit = fLimit(1);

      final handle = limit(
        () async {
          await Future.delayed(Duration(milliseconds: 10));
          return 'completed';
        },
        timeout: Duration(seconds: 1),
      );

      final result = await handle;
      expect(result, equals('completed'));
    });

    test('should support queue timeout through TaskTimeouts', () async {
      final limit = fLimit(1)..pause();

      final handle = limit(
        () async => 42,
        timeouts: TaskTimeouts(queue: Duration(milliseconds: 10)),
      );

      await expectLater(
        handle,
        throwsA(
          isA<TimeoutException>()
              .having((e) => e.stage, 'stage', TimeoutStage.queue),
        ),
      );
      expect(limit.pendingCount, equals(0));
      expect(handle.status, equals(TaskStatus.failed));
      expect(handle.isStarted, isFalse);
    });

    test('should support total timeout through TaskTimeouts', () async {
      final limit = fLimit(1);

      final handle = limit(
        () async {
          await Future.delayed(Duration(milliseconds: 50));
          return 42;
        },
        timeouts: TaskTimeouts(total: Duration(milliseconds: 10)),
      );

      await expectLater(
        handle,
        throwsA(
          isA<TimeoutException>()
              .having((e) => e.stage, 'stage', TimeoutStage.total),
        ),
      );
    });

    test('should keep isStarted false when total timeout happens in queue',
        () async {
      final limit = fLimit(1);

      final blocker = limit(() async {
        await Future.delayed(Duration(milliseconds: 50));
        return 0;
      });

      final handle = limit(
        () async => 42,
        timeouts: TaskTimeouts(total: Duration(milliseconds: 10)),
      );

      await expectLater(
        handle,
        throwsA(
          isA<TimeoutException>()
              .having((e) => e.stage, 'stage', TimeoutStage.total),
        ),
      );

      expect(handle.status, equals(TaskStatus.failed));
      expect(handle.isStarted, isFalse);
      expect(await blocker, equals(0));
    });

    test('should mark isStarted true for run timeout', () async {
      final limit = fLimit(1);

      final handle = limit(
        () async {
          await Future.delayed(Duration(milliseconds: 50));
          return 42;
        },
        timeouts: TaskTimeouts(run: Duration(milliseconds: 10)),
      );

      await expectLater(
        handle,
        throwsA(
          isA<TimeoutException>()
              .having((e) => e.stage, 'stage', TimeoutStage.run),
        ),
      );

      expect(handle.status, equals(TaskStatus.failed));
      expect(handle.isStarted, isTrue);
    });

    test('should reject timeout with timeouts.run', () {
      final limit = fLimit(1);

      expect(
        () => limit(
          () async => 42,
          timeout: Duration(seconds: 1),
          timeouts: TaskTimeouts(run: Duration(seconds: 1)),
        ),
        throwsArgumentError,
      );
    });
  });

  group('TaskTimeouts', () {
    test('should validate durations', () {
      expect(
        () => TaskTimeouts(queue: Duration(milliseconds: -1)),
        throwsArgumentError,
      );
      expect(
        () => TaskTimeouts(run: Duration(milliseconds: -1)),
        throwsArgumentError,
      );
      expect(
        () => TaskTimeouts(total: Duration(milliseconds: -1)),
        throwsArgumentError,
      );
    });
  });

  group('Lifecycle', () {
    test('close should cancel pending tasks and reject new submissions',
        () async {
      final limit = fLimit(1);

      final running = limit(() async {
        await Future.delayed(Duration(milliseconds: 30));
        return 1;
      });
      final pending = limit(() async => 2);

      await Future.delayed(Duration(milliseconds: 5));
      final closeFuture = limit.close();

      await expectLater(pending, throwsA(isA<CanceledException>()));
      expect(await running, equals(1));
      await closeFuture;

      expect(limit.isClosed, isTrue);
      expect(() => limit(() async => 3), throwsStateError);
    });

    test('dispose should drain queued work when cancelPending is false',
        () async {
      final limit = fLimit(1);
      final order = <int>[];

      limit(() async {
        order.add(1);
        await Future.delayed(Duration(milliseconds: 10));
      });
      limit(() async {
        order.add(2);
      });

      await limit.dispose(cancelPending: false);

      expect(order, equals([1, 2]));
      expect(limit.isClosed, isTrue);
      expect(() => limit(() async => 3), throwsStateError);
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
      final handles = <TaskHandle<void>>[];
      for (int i = 0; i < 5; i++) {
        handles.add(limit(() async {
          executionOrder.add(i);
          await Future.delayed(Duration(milliseconds: 10));
        }));
      }

      await Future.wait(handles);
      expect(executionOrder, equals([0, 1, 2, 3, 4]));
    });

    test('LIFO strategy should execute tasks in reverse order', () async {
      final limit = fLimit(1, queueStrategy: QueueStrategy.lifo);
      final executionOrder = <int>[];

      // Add tasks that record their execution order
      // Note: First task will execute immediately, others will be queued
      final handles = <TaskHandle<void>>[];
      for (int i = 0; i < 5; i++) {
        handles.add(limit(() async {
          executionOrder.add(i);
          await Future.delayed(Duration(milliseconds: 10));
        }));
        // Small delay to ensure queueing order
        if (i == 0) await Future.delayed(Duration(milliseconds: 20));
      }

      await Future.wait(handles);
      // First task executes immediately, then LIFO order for the rest
      expect(executionOrder, equals([0, 4, 3, 2, 1]));
    });

    test('Priority strategy should execute high priority tasks first',
        () async {
      final limit = fLimit(1, queueStrategy: QueueStrategy.priority);
      final executionOrder = <String>[];

      // Start with a blocking task
      final handles = <TaskHandle<void>>[];
      handles.add(limit(() async {
        executionOrder.add('blocking');
        await Future.delayed(Duration(milliseconds: 30));
      }));

      // Add tasks with different priorities while blocking task is running
      await Future.delayed(Duration(milliseconds: 10));

      handles.add(limit(() async {
        executionOrder.add('low-1');
        await Future.delayed(Duration(milliseconds: 5));
      }, priority: 1));

      handles.add(limit(() async {
        executionOrder.add('high-10');
        await Future.delayed(Duration(milliseconds: 5));
      }, priority: 10));

      handles.add(limit(() async {
        executionOrder.add('medium-5');
        await Future.delayed(Duration(milliseconds: 5));
      }, priority: 5));

      handles.add(limit(() async {
        executionOrder.add('high-10-2');
        await Future.delayed(Duration(milliseconds: 5));
      }, priority: 10));

      await Future.wait(handles);

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

      final limit = fLimit(1, queueStrategy: QueueStrategy.priority);

      // Start blocking task
      final handles = <TaskHandle<void>>[];
      handles.add(limit(() async {
        executionOrder.add('blocking');
        await Future.delayed(Duration(milliseconds: 20));
      }));

      // Queue tasks with different priorities
      // Priority: higher number = higher priority = executes first
      await Future.delayed(Duration(milliseconds: 5));
      handles.add(limit(() => taskB(), priority: 1)); // Low priority (1)
      handles.add(limit(() => taskA(), priority: 0)); // Lowest priority (0)
      handles.add(limit(() => taskA(), priority: 10)); // High priority (10)

      await Future.wait(handles);

      // Execution order: blocking, then by priority (10 > 1 > 0)
      expect(executionOrder, equals(['blocking', 'A', 'B', 'A']));
    });

    test(
        'Alternating strategy should execute tasks from head and tail alternately',
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
      final handles = tasks.map((task) => limit(task)).toList();

      await Future.wait(handles);

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
      final handles = tasks.map((task) => limit(task)).toList();

      await Future.wait(handles);

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

  group('onIdle', () {
    test('should return immediately if idle', () async {
      final limit = fLimit(1);
      bool completed = false;
      limit.onIdle.then((_) => completed = true);
      await Future.delayed(Duration.zero);
      expect(completed, isTrue);
    });

    test('should wait for tasks to complete', () async {
      final limit = fLimit(1);
      bool idle = false;

      limit(() async {
        await Future.delayed(Duration(milliseconds: 50));
      });

      limit.onIdle.then((_) => idle = true);

      await Future.delayed(Duration(milliseconds: 10));
      expect(idle, isFalse);

      await Future.delayed(Duration(milliseconds: 100));
      expect(idle, isTrue);
    });

    test('should wait for queued tasks', () async {
      final limit = fLimit(1);
      bool idle = false;

      // 1 active, 1 pending
      limit(() async => await Future.delayed(Duration(milliseconds: 50)));
      limit(() async => await Future.delayed(Duration(milliseconds: 50)));

      limit.onIdle.then((_) => idle = true);

      await Future.delayed(Duration(milliseconds: 10));
      expect(idle, isFalse);

      await Future.delayed(
          Duration(milliseconds: 60)); // First done, second active
      expect(idle, isFalse);

      await Future.delayed(Duration(milliseconds: 60)); // Both done
      expect(idle, isTrue);
    });
  });
}
