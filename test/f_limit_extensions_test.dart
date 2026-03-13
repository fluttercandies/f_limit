import 'package:f_limit/f_limit.dart';
import 'package:test/test.dart';

void main() {
  group('FLimitExtensions', () {
    group('map', () {
      test('should map items with concurrency limit', () async {
        final limit = fLimit(2);
        int activeCount = 0;
        int maxActiveCount = 0;

        final items = [1, 2, 3, 4, 5];
        final results = await limit.map(items, (item) async {
          activeCount++;
          if (activeCount > maxActiveCount) maxActiveCount = activeCount;
          await Future.delayed(Duration(milliseconds: 10));
          activeCount--;
          return item * 2;
        });

        expect(results, equals([2, 4, 6, 8, 10]));
        expect(maxActiveCount, equals(2));
      });

      test('should maintain order', () async {
        final limit = fLimit(2);
        final items = [1, 2, 3, 4, 5];

        final results = await limit.map(items, (item) async {
          // Add random delay to mix up completion times
          await Future.delayed(Duration(milliseconds: 10 * (6 - item)));
          return item;
        });

        expect(results, equals(items));
      });

      test('should support retry', () async {
        final limit = fLimit(1);
        final items = [1, 2];
        final attempts = <int>[];

        final results = await limit.map(
          items,
          (item) async {
            attempts.add(item);
            if (attempts.where((i) => i == item).length < 2) {
              throw Exception('Retry needed');
            }
            return item * 2;
          },
          retry: RetrySimple(maxAttempts: 2),
        );

        expect(results, equals([2, 4]));
      });

      test('should support timeout', () async {
        final limit = fLimit(1);

        final results = await limit.map(
          [1, 2],
          (item) async {
            await Future.delayed(Duration(milliseconds: 10));
            return item * 2;
          },
          timeout: Duration(seconds: 1),
        );

        expect(results, equals([2, 4]));
      });

      test('should support TaskTimeouts named parameter', () async {
        final limit = fLimit(1);

        final results = await limit.map(
          [1, 2],
          (item) async {
            await Future.delayed(Duration(milliseconds: 10));
            return item * 2;
          },
          timeouts: TaskTimeouts(run: Duration(seconds: 1)),
        );

        expect(results, equals([2, 4]));
      });
    });

    group('settled', () {
      test('mapSettled should capture success and failure', () async {
        final limit = fLimit(2);

        final results = await limit.mapSettled([1, 2, 3], (item) async {
          if (item == 2) {
            throw StateError('boom');
          }
          return item * 2;
        });

        expect(results, hasLength(3));
        expect(results[0].status, equals(TaskStatus.completed));
        expect(results[0].value, equals(2));
        expect(results[1].status, equals(TaskStatus.failed));
        expect(results[1].error, isA<StateError>());
        expect(results[2].status, equals(TaskStatus.completed));
        expect(results[2].value, equals(6));
      });

      test('forEachSettled should capture action failures', () async {
        final limit = fLimit(2);
        final processed = <int>[];

        final results = await limit.forEachSettled([1, 2, 3], (item) async {
          processed.add(item);
          if (item == 2) {
            throw StateError('boom');
          }
        });

        expect(processed.toSet(), equals({1, 2, 3}));
        expect(
            results.map((result) => result.status).toList(),
            equals([
              TaskStatus.completed,
              TaskStatus.failed,
              TaskStatus.completed,
            ]));
        expect(results[1].error, isA<StateError>());
      });
    });

    group('forEach', () {
      test('should execute action for each item', () async {
        final limit = fLimit(2);
        final processed = <int>[];

        await limit.forEach([1, 2, 3, 4, 5], (item) async {
          processed.add(item);
        });

        expect(processed.toSet(), equals({1, 2, 3, 4, 5}));
      });

      test('should respect concurrency limit', () async {
        final limit = fLimit(2);
        int activeCount = 0;
        int maxActiveCount = 0;

        await limit.forEach([1, 2, 3, 4, 5], (item) async {
          activeCount++;
          if (activeCount > maxActiveCount) maxActiveCount = activeCount;
          await Future.delayed(Duration(milliseconds: 10));
          activeCount--;
        });

        expect(maxActiveCount, equals(2));
      });
    });

    group('filter', () {
      test('should filter items based on predicate', () async {
        final limit = fLimit(2);
        final items = [1, 2, 3, 4, 5, 6];

        final evens = await limit.filter(items, (item) async {
          return item % 2 == 0;
        });

        expect(evens, equals([2, 4, 6]));
      });

      test('should preserve order', () async {
        final limit = fLimit(3);
        final items = [5, 3, 1, 4, 2];

        final filtered = await limit.filter(items, (item) async {
          // Add varying delays
          await Future.delayed(Duration(milliseconds: 10 * item));
          return item > 2;
        });

        expect(filtered, equals([5, 3, 4]));
      });

      test('should return empty list when nothing matches', () async {
        final limit = fLimit(2);

        final filtered = await limit.filter([1, 2, 3], (item) async {
          return item > 10;
        });

        expect(filtered, isEmpty);
      });
    });

    group('mapIndexed', () {
      test('should provide index to mapper', () async {
        final limit = fLimit(2);
        final items = ['a', 'b', 'c'];

        final results = await limit.mapIndexed(items, (index, item) async {
          return '$index:$item';
        });

        expect(results, equals(['0:a', '1:b', '2:c']));
      });

      test('should maintain order', () async {
        final limit = fLimit(2);
        final items = ['a', 'b', 'c'];

        final results = await limit.mapIndexed(items, (index, item) async {
          await Future.delayed(Duration(milliseconds: 10 * (3 - index)));
          return '$index:$item';
        });

        expect(results, equals(['0:a', '1:b', '2:c']));
      });
    });

    group('reduce', () {
      test('should reduce items to single value', () async {
        final limit = fLimit(2);
        final items = [1, 2, 3, 4, 5];

        final sum = await limit.reduce(items, (a, b) async {
          return a + b;
        });

        expect(sum, equals(15));
      });

      test('should throw on empty list', () async {
        final limit = fLimit(2);

        expect(
          () => limit.reduce([], (a, b) async => a + b),
          throwsStateError,
        );
      });

      test('should return single element unchanged', () async {
        final limit = fLimit(2);

        final result = await limit.reduce([42], (a, b) async => a + b);

        expect(result, equals(42));
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

      test('should handle multiple onIdle callers', () async {
        final limit = fLimit(1);
        int completedCount = 0;

        limit(() async {
          await Future.delayed(Duration(milliseconds: 30));
        });

        // Multiple callers waiting for idle
        limit.onIdle.then((_) => completedCount++);
        limit.onIdle.then((_) => completedCount++);
        limit.onIdle.then((_) => completedCount++);

        await Future.delayed(Duration(milliseconds: 10));
        expect(completedCount, equals(0));

        await Future.delayed(Duration(milliseconds: 50));
        expect(completedCount, equals(3));
      });
    });
  });
}
