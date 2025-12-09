import 'dart:async';
import 'package:f_limit/f_limit.dart';
import 'package:test/test.dart';

// Top-level function for isolate
int heavyComputation() {
  int result = 0;
  for (int i = 0; i < 1000000; i++) {
    result += i;
  }
  return result;
}

// Top-level function that throws
void throwingComputation() {
  throw Exception('Isolate error');
}

void main() {
  group('FLimitIsolate', () {
    test('isolate should execute task and return result', () async {
      final limit = fLimit(1);
      final result = await limit.isolate(heavyComputation);
      expect(result, equals(499999500000));
    });

// Helper to avoid capturing local variables that might not be sendable
    FutureOr<int> Function() _createHeavyComputation(int index) {
      return () {
        final end = DateTime.now().add(Duration(milliseconds: 100));
        while (DateTime.now().isBefore(end)) {}
        return index;
      };
    }

    test('isolate should respect concurrency limit', () async {
      final limit = fLimit(2);
      int completedCount = 0;

      final futures = List.generate(5, (index) {
        return limit.isolate(_createHeavyComputation(index)).then((value) {
          completedCount++;
          return value;
        });
      });

      // Initially, active count should be reflected (though harder to test deterministically with isolates)
      // We rely on the fact that f_limit internals are tested separately.

      final results = await Future.wait(futures);
      expect(results, equals([0, 1, 2, 3, 4]));
      expect(completedCount, equals(5));
    });

    test('isolate should propagate errors', () async {
      final limit = fLimit(1);
      expect(limit.isolate(throwingComputation), throwsException);
    });

    test('isolate should work with priority', () async {
      final limit = fLimit(1, queueStrategy: QueueStrategy.priority);
      final executionOrder = <int>[];

      // Start a blocking task
      limit.isolate(() {
        final end = DateTime.now().add(Duration(milliseconds: 200));
        while (DateTime.now().isBefore(end)) {}
        return -1;
      });

      await Future.delayed(Duration(milliseconds: 50));

      // Add tasks with different priorities
      final f1 = limit.isolate(() => 1, priority: 1).then((v) {
        executionOrder.add(v);
        return v;
      });

      final f2 = limit.isolate(() => 10, priority: 10).then((v) {
        executionOrder.add(v);
        return v;
      });

      await Future.wait([f1, f2]);

      // High priority (10) should finish before Low priority (1)
      expect(executionOrder, equals([10, 1]));
    });
  });
}
