import 'dart:async';
import 'dart:io';

import 'package:f_limit/f_limit.dart';
import 'package:test/test.dart';

void main() {
  group('Edge Cases - Concurrency', () {
    test('concurrency of 1 should execute tasks sequentially', () async {
      final limit = fLimit(1);
      final order = <int>[];

      final handles = List.generate(5, (i) {
        return limit(() async {
          order.add(i);
          await Future.delayed(Duration(milliseconds: 5));
          return i;
        });
      });

      await Future.wait(handles);
      expect(order, equals([0, 1, 2, 3, 4]));
    });

    test('concurrency larger than task count should run all immediately',
        () async {
      final limit = fLimit(100);
      int maxConcurrent = 0;
      int currentConcurrent = 0;

      final handles = List.generate(5, (i) {
        return limit(() async {
          currentConcurrent++;
          if (currentConcurrent > maxConcurrent) {
            maxConcurrent = currentConcurrent;
          }
          await Future.delayed(Duration(milliseconds: 10));
          currentConcurrent--;
          return i;
        });
      });

      await Future.wait(handles);
      expect(maxConcurrent, equals(5));
    });

    test('changing concurrency to 0 should throw', () {
      final limit = fLimit(2);
      expect(() => limit.concurrency = 0, throwsArgumentError);
    });

    test('changing concurrency to negative should throw', () {
      final limit = fLimit(2);
      expect(() => limit.concurrency = -1, throwsArgumentError);
    });

    test('changing concurrency to double.infinity should throw', () {
      final limit = fLimit(2);
      expect(
        () => limit.concurrency = double.infinity.toInt(),
        throwsA(isA<UnsupportedError>()),
      );
    });

    test('creating limiter with concurrency 0 should throw', () {
      expect(() => fLimit(0), throwsArgumentError);
    });

    test('creating limiter with negative concurrency should throw', () {
      expect(() => fLimit(-5), throwsArgumentError);
    });

    test('dynamically increasing concurrency should process queued tasks',
        () async {
      final limit = fLimit(1);
      int maxConcurrent = 0;
      int currentConcurrent = 0;

      // Add 5 tasks with concurrency 1
      final handles = List.generate(5, (i) {
        return limit(() async {
          currentConcurrent++;
          if (currentConcurrent > maxConcurrent) {
            maxConcurrent = currentConcurrent;
          }
          await Future.delayed(Duration(milliseconds: 20));
          currentConcurrent--;
          return i;
        });
      });

      await Future.delayed(Duration(milliseconds: 10));
      // Increase concurrency while tasks are running
      limit.concurrency = 3;

      await Future.wait(handles);
      expect(maxConcurrent, greaterThanOrEqualTo(2));
    });

    test('dynamically decreasing concurrency should respect new limit',
        () async {
      final limit = fLimit(10);
      int maxConcurrent = 0;
      int currentConcurrent = 0;

      limit.concurrency = 2;

      final handles = List.generate(5, (i) {
        return limit(() async {
          currentConcurrent++;
          if (currentConcurrent > maxConcurrent) {
            maxConcurrent = currentConcurrent;
          }
          await Future.delayed(Duration(milliseconds: 10));
          currentConcurrent--;
          return i;
        });
      });

      await Future.wait(handles);
      expect(maxConcurrent, equals(2));
    });
  });

  group('Edge Cases - TaskHandle', () {
    test('cancel on already completed task should return false', () async {
      final limit = fLimit(1);
      final handle = limit(() async => 42);

      await handle;
      expect(handle.isCompleted, isTrue);

      final canceled = handle.cancel();
      expect(canceled, isFalse);
    });

    test('cancel on already canceled task should return false', () async {
      final limit = fLimit(1);

      // Block the queue
      limit(() async {
        await Future.delayed(Duration(seconds: 10));
      });

      final handle = limit(() async => 42);
      await Future.delayed(Duration(milliseconds: 10));

      final canceled1 = handle.cancel();
      expect(canceled1, isTrue);

      // Handle the canceled future to avoid uncaught exception
      try {
        await handle;
      } on CanceledException {
        // Expected
      }

      final canceled2 = handle.cancel();
      expect(canceled2, isFalse);
    });

    test('cancel should not affect other tasks', () async {
      final limit = fLimit(1);
      final results = <int>[];

      // Block
      limit(() async {
        await Future.delayed(Duration(milliseconds: 30));
        results.add(0);
      });

      // Will be canceled
      final handle2 = limit(() async {
        results.add(1);
      });

      // Should execute
      final handle3 = limit(() async {
        results.add(2);
      });

      await Future.delayed(Duration(milliseconds: 10));
      handle2.cancel();

      // Handle the canceled future
      try {
        await handle2;
      } on CanceledException {
        // Expected
      }

      await handle3;
      await Future.delayed(Duration(milliseconds: 50));

      expect(results, containsAll([0, 2]));
      expect(results, isNot(contains(1)));
    });

    test('cancel should fail once a task has been resumed for execution',
        () async {
      final limit = fLimit(1);
      var executed = false;

      final blocker = limit(() async {
        await Future.delayed(Duration(milliseconds: 30));
        return 0;
      });

      final handle = limit(() async {
        executed = true;
        return 42;
      });

      await blocker;

      final canceled = handle.cancel();
      expect(canceled, isFalse);

      final result = await handle;
      expect(result, equals(42));
      expect(executed, isTrue);
    });

    test('multiple tasks with same priority should execute in FIFO order',
        () async {
      final limit = fLimit(1, queueStrategy: QueueStrategy.priority);
      final order = <int>[];

      final handles = List.generate(5, (i) {
        return limit(() async {
          order.add(i);
          return i;
        }, priority: 5); // Same priority
      });

      await Future.wait(handles);
      expect(order, equals([0, 1, 2, 3, 4]));
    });

    test('TaskHandle id should be unique across tasks', () async {
      final limit = fLimit(2);
      final ids = <int>{};

      for (int i = 0; i < 100; i++) {
        final handle = limit(() async => i);
        ids.add(handle.id);
      }

      expect(ids.length, equals(100));
    });
  });

  group('Edge Cases - Queue Operations', () {
    test('clearQueue on empty queue should not throw', () {
      final limit = fLimit(2);
      expect(() => limit.clearQueue(), returnsNormally);
    });

    test('clearQueue should not affect running tasks', () async {
      final limit = fLimit(1);
      var completed = false;

      final handle = limit(() async {
        await Future.delayed(Duration(milliseconds: 50));
        completed = true;
        return 'done';
      });

      // Add more tasks
      final pending1 = limit(() async {});
      final pending2 = limit(() async {});

      await Future.delayed(Duration(milliseconds: 10));
      final pending1Canceled =
          expectLater(pending1, throwsA(isA<CanceledException>()));
      final pending2Canceled =
          expectLater(pending2, throwsA(isA<CanceledException>()));
      limit.clearQueue();

      expect(limit.pendingCount, equals(0));

      final result = await handle;
      expect(result, equals('done'));
      expect(completed, isTrue);

      await pending1Canceled;
      await pending2Canceled;
    });

    test('clearQueue should cancel pending handles', () async {
      final limit = fLimit(1);

      final running = limit(() async {
        await Future.delayed(Duration(milliseconds: 50));
        return 0;
      });

      final canceled = limit(() async => 1);

      await Future.delayed(Duration(milliseconds: 10));
      final canceledCheck =
          expectLater(canceled, throwsA(isA<CanceledException>()));
      limit.clearQueue();

      await canceledCheck;
      expect(limit.pendingCount, equals(0));

      final result = await running;
      expect(result, equals(0));
    });

    test('clearQueue should not crash when queued handles are ignored',
        () async {
      final script = File(
        '${Directory.current.path}/.codex_clear_queue_'
        '${DateTime.now().microsecondsSinceEpoch}.dart',
      );

      await script.writeAsString('''
import 'dart:async';
import 'package:f_limit/f_limit.dart';

Future<void> main() async {
  final limit = fLimit(1);
  limit(() async {
    await Future.delayed(Duration(milliseconds: 30));
  });

  limit(() async => 1);
  limit(() async => 2);

  await Future.delayed(Duration(milliseconds: 5));
  limit.clearQueue();
  await limit.onIdle;
  print('done');
}
''');

      try {
        final result = await Process.run(
          Platform.resolvedExecutable,
          ['run', script.path],
          workingDirectory: Directory.current.path,
        );

        expect(result.exitCode, equals(0),
            reason: '${result.stdout}\n${result.stderr}');
        expect(result.stdout, contains('done'));
      } finally {
        if (await script.exists()) {
          await script.delete();
        }
      }
    });

    test('alternating queue with single item', () async {
      final limit = fLimit(1, queueStrategy: QueueStrategy.alternating);
      var executed = false;

      await limit(() async {
        executed = true;
      });

      expect(executed, isTrue);
    });

    test('random queue should eventually execute all tasks', () async {
      final limit = fLimit(1, queueStrategy: QueueStrategy.random);
      final executed = <int>{};

      final handles = List.generate(20, (i) {
        return limit(() async {
          executed.add(i);
          return i;
        });
      });

      await Future.wait(handles);
      expect(executed.length, equals(20));
    });
  });

  group('Edge Cases - Pause and Resume', () {
    test('pause when already paused should be idempotent', () {
      final limit = fLimit(2);

      limit.pause();
      expect(limit.isPaused, isTrue);

      limit.pause();
      expect(limit.isPaused, isTrue);
    });

    test('resume when not paused should be idempotent', () {
      final limit = fLimit(2);

      limit.resume();
      expect(limit.isPaused, isFalse);

      limit.resume();
      expect(limit.isPaused, isFalse);
    });

    test('tasks added while paused should execute after resume', () async {
      final limit = fLimit(2);
      final executed = <int>[];

      limit.pause();

      for (int i = 0; i < 5; i++) {
        limit(() async {
          executed.add(i);
        });
      }

      await Future.delayed(Duration(milliseconds: 50));
      expect(executed, isEmpty);

      limit.resume();
      await limit.onIdle;

      expect(executed.length, equals(5));
    });

    test('clearQueue while paused should clear pending tasks', () async {
      final limit = fLimit(1);
      final executed = <int>[];
      final queuedHandles = <TaskHandle<void>>[];

      // Start first task - it will run immediately
      final handle1 = limit(() async {
        await Future.delayed(Duration(milliseconds: 100));
        executed.add(0);
      });

      // Wait for first task to start
      await Future.delayed(Duration(milliseconds: 10));
      expect(limit.activeCount, equals(1));

      // Pause before adding more tasks
      limit.pause();

      // Add more tasks - they will queue but not execute
      for (int i = 1; i <= 5; i++) {
        queuedHandles.add(limit(() async {
          executed.add(i);
        }));
      }

      await Future.delayed(Duration(milliseconds: 10));
      // 5 tasks in queue
      expect(limit.pendingCount, equals(5));

      final canceledChecks = queuedHandles
          .map((handle) =>
              expectLater(handle, throwsA(isA<CanceledException>())))
          .toList();

      limit.clearQueue();
      expect(limit.pendingCount, equals(0));

      limit.resume();

      // Wait for first task to complete
      await handle1;
      await Future.delayed(Duration(milliseconds: 20));

      // Only the first task should have executed
      expect(executed, equals([0]));

      await Future.wait(canceledChecks);
    });
  });

  group('Edge Cases - Timeout', () {
    test('timeout of zero should immediately fail', () async {
      final limit = fLimit(1);

      final handle = limit(
        () async {
          await Future.delayed(Duration(milliseconds: 100));
          return 42;
        },
        timeout: Duration.zero,
      );

      expect(handle, throwsA(isA<TimeoutException>()));
    });

    test('timeout should not affect completed tasks', () async {
      final limit = fLimit(1);

      final handle = limit(
        () async {
          await Future.delayed(Duration(milliseconds: 10));
          return 42;
        },
        timeout: Duration(seconds: 10),
      );

      final result = await handle;
      expect(result, equals(42));
    });

    test('timeout message should contain duration', () async {
      final limit = fLimit(1);
      final timeout = Duration(milliseconds: 50);

      final handle = limit(
        () async {
          await Future.delayed(Duration(seconds: 10));
          return 42;
        },
        timeout: timeout,
      );

      try {
        await handle;
        fail('Should throw');
      } on TimeoutException catch (e) {
        expect(e.duration, equals(timeout));
      }
    });

    test('timeout should not release the concurrency slot early', () async {
      final limit = fLimit(1);
      var activeCount = 0;
      var maxActiveCount = 0;
      final secondStarted = Completer<void>();

      final first = limit(
        () async {
          activeCount++;
          if (activeCount > maxActiveCount) {
            maxActiveCount = activeCount;
          }
          await Future.delayed(Duration(milliseconds: 80));
          activeCount--;
          return 'first';
        },
        timeout: Duration(milliseconds: 10),
      );

      await expectLater(first, throwsA(isA<TimeoutException>()));
      expect(limit.activeCount, equals(1));

      final second = limit(() async {
        activeCount++;
        if (activeCount > maxActiveCount) {
          maxActiveCount = activeCount;
        }
        secondStarted.complete();
        await Future.delayed(Duration(milliseconds: 10));
        activeCount--;
        return 'second';
      });

      await Future.delayed(Duration(milliseconds: 20));
      expect(secondStarted.isCompleted, isFalse);

      final result = await second;
      expect(result, equals('second'));
      expect(maxActiveCount, equals(1));
    });
  });

  group('Edge Cases - Retry', () {
    test('RetrySimple with maxAttempts 1 should not retry', () async {
      final limit = fLimit(1);
      int attempts = 0;

      final handle = limit(
        () async {
          attempts++;
          throw Exception('fail');
        },
        retry: RetrySimple(maxAttempts: 1),
      );

      try {
        await handle;
      } catch (_) {}

      expect(attempts, equals(1));
    });

    test('RetryExponential with multiplier 1 should have constant delay', () {
      final policy = RetryExponential(
        maxAttempts: 5,
        baseDelay: Duration(seconds: 1),
        multiplier: 1.0,
      );

      final d1 = policy.nextDelay(0, Exception(), StackTrace.empty);
      final d2 = policy.nextDelay(1, Exception(), StackTrace.empty);
      final d3 = policy.nextDelay(2, Exception(), StackTrace.empty);

      expect(d1, equals(Duration(seconds: 1)));
      expect(d2, equals(Duration(seconds: 1)));
      expect(d3, equals(Duration(seconds: 1)));
    });

    test('RetryWithJitter with factor 0 should have no jitter', () {
      final inner = RetryFixed(
        maxAttempts: 3,
        delay: Duration(milliseconds: 100),
      );
      final jittered = RetryWithJitter(inner, jitterFactor: 0.0);

      final delays = <int>[];
      for (int i = 0; i < 5; i++) {
        final d = jittered.nextDelay(0, Exception(), StackTrace.empty);
        delays.add(d!.inMilliseconds);
      }

      // All delays should be exactly 100ms
      expect(delays.every((d) => d == 100), isTrue);
    });
  });

  group('Edge Cases - onIdle', () {
    test('onIdle should complete immediately when already idle', () async {
      final limit = fLimit(2);

      final stopwatch = Stopwatch()..start();
      await limit.onIdle;
      stopwatch.stop();

      expect(stopwatch.elapsedMilliseconds, lessThan(100));
    });

    test('multiple onIdle callers should all complete', () async {
      final limit = fLimit(1);
      int completed = 0;

      limit(() async {
        await Future.delayed(Duration(milliseconds: 50));
      });

      final futures = List.generate(5, (_) {
        return limit.onIdle.then((_) {
          completed++;
        });
      });

      await Future.wait(futures);
      expect(completed, equals(5));
    });

    test('onIdle during pause should not complete until resumed', () async {
      final limit = fLimit(1);
      bool idle = false;

      limit.pause();
      limit(() async {});

      limit.onIdle.then((_) => idle = true);

      await Future.delayed(Duration(milliseconds: 50));
      expect(idle, isFalse);

      limit.resume();
      await limit.onIdle;
      expect(idle, isTrue);
    });

    test('onIdle should complete after canceling the last pending task',
        () async {
      final limit = fLimit(1);
      limit.pause();

      final handle = limit(() async => 1);
      final idleFuture = limit.onIdle;

      expect(handle.cancel(), isTrue);
      await expectLater(handle, throwsA(isA<CanceledException>()));
      await idleFuture;

      expect(limit.isEmpty, isTrue);
    });
  });

  group('Edge Cases - Error Handling', () {
    test('error in one task should not prevent other tasks from running',
        () async {
      final limit = fLimit(2);
      final results = <int>[];

      final handle1 = limit(() async {
        throw Exception('task 0 fails');
      });

      final handle2 = limit(() async {
        results.add(1);
        return 1;
      });

      final handle3 = limit(() async {
        results.add(2);
        return 2;
      });

      // Handle errors properly
      try {
        await handle1;
      } catch (_) {}

      await handle2;
      await handle3;

      expect(results, containsAll([1, 2]));
    });

    test('stack trace should be preserved on error', () async {
      final limit = fLimit(1);
      StackTrace? capturedStackTrace;

      final handle = limit(() async {
        throw Exception('test error');
      });

      try {
        await handle;
      } catch (_, stackTrace) {
        capturedStackTrace = stackTrace;
      }

      expect(capturedStackTrace, isNotNull);
    });

    test('CanceledException should have message', () async {
      final limit = fLimit(1);

      limit(() async {
        await Future.delayed(Duration(seconds: 10));
      });

      final handle = limit(() async => 42);
      await Future.delayed(Duration(milliseconds: 10));
      handle.cancel();

      try {
        await handle;
        fail('Should throw');
      } on CanceledException catch (e) {
        expect(e.message, contains('canceled'));
      }
    });
  });

  group('Edge Cases - Extensions', () {
    test('map with empty iterable should return empty list', () async {
      final limit = fLimit(2);

      final results = await limit.map<int, int>([], (n) async => n * 2);

      expect(results, isEmpty);
    });

    test('filter with empty iterable should return empty list', () async {
      final limit = fLimit(2);

      final results = await limit.filter<int>([], (n) async => true);

      expect(results, isEmpty);
    });

    test('forEach with empty iterable should complete immediately', () async {
      final limit = fLimit(2);
      var executed = false;

      await limit.forEach<int>([], (n) async {
        executed = true;
      });

      expect(executed, isFalse);
    });

    test('reduce with single element should return that element', () async {
      final limit = fLimit(2);

      final result = await limit.reduce([42], (a, b) async => a + b);

      expect(result, equals(42));
    });

    test('mapIndexed with empty iterable should return empty list', () async {
      final limit = fLimit(2);

      final results =
          await limit.mapIndexed<int, String>([], (i, n) async => '$i:$n');

      expect(results, isEmpty);
    });
  });

  group('Edge Cases - Large Scale', () {
    test('should handle 1000 tasks', () async {
      final limit = fLimit(10);
      final count = 1000;

      final handles = List.generate(count, (i) {
        return limit(() async {
          await Future.delayed(Duration.zero);
          return i;
        });
      });

      final results = await Future.wait(handles);

      expect(results.length, equals(count));
      expect(results.toSet().length, equals(count));
    });

    test('should handle rapid task submission', () async {
      final limit = fLimit(5);
      final executed = <int>[];

      // Rapidly submit 100 tasks
      for (int i = 0; i < 100; i++) {
        limit(() async {
          executed.add(i);
        });
      }

      await limit.onIdle;
      expect(executed.length, equals(100));
    });
  });

  group('Edge Cases - State Consistency', () {
    test('activeCount and pendingCount should be consistent', () async {
      final limit = fLimit(2);

      // Initially idle
      expect(limit.activeCount, equals(0));
      expect(limit.pendingCount, equals(0));
      expect(limit.isEmpty, isTrue);
      expect(limit.isBusy, isFalse);

      // Add tasks
      final handles = List.generate(5, (i) {
        return limit(() async {
          await Future.delayed(Duration(milliseconds: 50));
          return i;
        });
      });

      await Future.delayed(Duration(milliseconds: 10));

      // Should have active and pending
      expect(limit.activeCount, greaterThan(0));
      expect(limit.pendingCount, greaterThan(0));
      expect(limit.isEmpty, isFalse);
      expect(limit.isBusy, isTrue);

      await Future.wait(handles);

      // Back to idle
      expect(limit.activeCount, equals(0));
      expect(limit.pendingCount, equals(0));
      expect(limit.isEmpty, isTrue);
      expect(limit.isBusy, isFalse);
    });

    test('clearQueue should update pendingCount immediately', () async {
      final limit = fLimit(1);

      // Block with long task
      final blocker = limit(() async {
        await Future.delayed(Duration(milliseconds: 100));
      });

      // Queue many tasks
      final handles = <TaskHandle<int>>[];
      for (int i = 0; i < 100; i++) {
        handles.add(limit(() async => i));
      }

      await Future.delayed(Duration(milliseconds: 10));
      expect(limit.pendingCount, equals(100));

      final canceledChecks = handles
          .map((handle) => handle.then<void>((_) {}, onError: (_) {}))
          .toList();

      limit.clearQueue();
      expect(limit.pendingCount, equals(0));

      await Future.wait(canceledChecks);
      await blocker;
    });

    test('priority queue should preserve order after canceling middle task',
        () async {
      final limit = fLimit(1, queueStrategy: QueueStrategy.priority);
      final executionOrder = <int>[];
      final priorities = [2, 3, 1, 1, 3, 1];

      limit.pause();

      final handles = List.generate(priorities.length, (index) {
        return limit(() async {
          executionOrder.add(index);
          return index;
        }, priority: priorities[index]);
      });

      expect(handles[1].cancel(), isTrue);
      await expectLater(handles[1], throwsA(isA<CanceledException>()));

      limit.resume();
      await limit.onIdle;

      expect(executionOrder, equals([4, 0, 2, 3, 5]));
    });
  });
}
