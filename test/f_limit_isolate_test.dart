import 'dart:async';

import 'package:f_limit/f_limit.dart';
import 'package:test/test.dart';

// Top-level functions for isolate (must be top-level for isolate constraints)

int _heavyComputation() {
  int result = 0;
  for (int i = 0; i < 1000000; i++) {
    result += i;
  }
  return result;
}

int _throwingComputation() {
  throw Exception('Isolate error');
}

int _return42() => 42;

int _return1() => 1;

int _return2() => 2;

int _return10() => 10;

int _blockingComputation() {
  final end = DateTime.now().add(Duration(milliseconds: 200));
  while (DateTime.now().isBefore(end)) {}
  return -1;
}

int _longComputation() {
  final end = DateTime.now().add(Duration(seconds: 10));
  while (DateTime.now().isBefore(end)) {}
  return 42;
}

void main() {
  group('FLimitIsolate', () {
    test('isolate should execute task and return result', () async {
      final limit = fLimit(1);
      final handle = limit.isolate(_heavyComputation);

      expect(handle, isA<TaskHandle<int>>());
      final result = await handle;
      expect(result, equals(499999500000));
    });

    test('isolate should respect concurrency limit', () async {
      final limit = fLimit(2);

      // Use only top-level functions without closures
      final handles = [
        limit.isolate(_return1),
        limit.isolate(_return2),
        limit.isolate(_return10),
        limit.isolate(_return42),
      ];

      final results = await Future.wait(handles);

      expect(results, containsAll([1, 2, 10, 42]));
    });

    test('isolate should propagate errors', () async {
      final limit = fLimit(1);
      final handle = limit.isolate(_throwingComputation);

      try {
        await handle;
        fail('Should have thrown');
      } catch (e) {
        expect(e, isException);
      }
    });

    test('isolate should work with priority', () async {
      final limit = fLimit(1, queueStrategy: QueueStrategy.priority);
      final executionOrder = <int>[];

      // Start a blocking task
      limit.isolate(_blockingComputation);

      await Future.delayed(Duration(milliseconds: 50));

      // Add tasks with different priorities
      final f1 = limit.isolate(_return1, priority: 1).then((v) {
        executionOrder.add(v);
        return v;
      });

      final f2 = limit.isolate(_return10, priority: 10).then((v) {
        executionOrder.add(v);
        return v;
      });

      await Future.wait([f1, f2]);

      // High priority (10) should finish before Low priority (1)
      expect(executionOrder, equals([10, 1]));
    });

    test('isolate should return TaskHandle', () async {
      final limit = fLimit(1);
      final handle = limit.isolate(_return42);

      expect(handle.isCompleted, isFalse);

      final result = await handle;

      expect(result, equals(42));
      expect(handle.isCompleted, isTrue);
    });

    test('isolate should support timeout', () async {
      final limit = fLimit(1);

      final handle = limit.isolate(
        _longComputation,
        timeout: Duration(milliseconds: 50),
      );

      try {
        await handle;
        fail('Should have thrown TimeoutException');
      } on TimeoutException {
        // Expected
      }
    });

    test('isolate should support TaskTimeouts', () async {
      final limit = fLimit(1);

      final handle = limit.isolate(
        _longComputation,
        timeouts: TaskTimeouts(run: Duration(milliseconds: 50)),
      );

      await expectLater(
        handle,
        throwsA(
          isA<TimeoutException>()
              .having((e) => e.stage, 'stage', TimeoutStage.run),
        ),
      );
    });

    test('isolate should work with retry', () async {
      final limit = fLimit(1);

      // Note: Retry with isolate is limited because the computation
      // runs in a separate isolate and cannot capture local variables.
      // Here we test the basic retry functionality.
      final handle = limit.isolate(
        _return42,
        retry: RetrySimple(maxAttempts: 2),
      );

      final result = await handle;
      expect(result, equals(42));
    });

    test('isolate handle should be cancelable before execution', () async {
      final limit = fLimit(1);

      // Start a long task
      limit.isolate(_longComputation);

      // Add another task that we'll try to cancel
      final cancelableHandle = limit.isolate(_return2);

      // Give time for first task to start
      await Future.delayed(Duration(milliseconds: 10));

      // Second task is pending, should be cancelable
      final canceled = cancelableHandle.cancel();
      expect(canceled, isTrue);
      expect(cancelableHandle.isCanceled, isTrue);

      // Future should throw CanceledException
      try {
        await cancelableHandle;
        fail('Should have thrown CanceledException');
      } on CanceledException {
        // Expected
      }

      // Clean up - clear the queue
      limit.clearQueue();
    });
  });
}
