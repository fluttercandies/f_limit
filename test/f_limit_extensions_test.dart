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
  });
}
