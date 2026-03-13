import 'package:f_limit/f_limit.dart';
import 'package:test/test.dart';

void main() {
  group('RetryPolicy', () {
    group('validation', () {
      test('should validate retry policy parameters', () {
        expect(() => RetrySimple(maxAttempts: 0), throwsArgumentError);
        expect(
          () => RetryFixed(
            maxAttempts: 1,
            delay: Duration(milliseconds: -1),
          ),
          throwsArgumentError,
        );
        expect(
          () => RetryExponential(
            maxAttempts: 1,
            baseDelay: Duration(milliseconds: -1),
          ),
          throwsArgumentError,
        );
        expect(
          () => RetryExponential(
            maxAttempts: 1,
            baseDelay: Duration(milliseconds: 1),
            multiplier: 0,
          ),
          throwsArgumentError,
        );
        expect(
          () => RetryWithJitter(
            RetrySimple(maxAttempts: 1),
            jitterFactor: 1.5,
          ),
          throwsArgumentError,
        );
      });
    });

    group('RetrySimple', () {
      test('should retry up to max attempts', () async {
        final limit = fLimit(1);
        int attempts = 0;

        final handle = limit(
          () async {
            attempts++;
            if (attempts < 3) {
              throw Exception('Not yet');
            }
            return 'success';
          },
          retry: RetrySimple(maxAttempts: 3),
        );

        final result = await handle;
        expect(result, equals('success'));
        expect(attempts, equals(3));
      });

      test('should fail after max attempts', () async {
        final limit = fLimit(1);
        int attempts = 0;

        final handle = limit(
          () async {
            attempts++;
            throw Exception('Always fails');
          },
          retry: RetrySimple(maxAttempts: 3),
        );

        expect(handle, throwsException);
        try {
          await handle;
        } catch (_) {}
        expect(attempts, equals(3));
      });

      test('should not retry on success', () async {
        final limit = fLimit(1);
        int attempts = 0;

        final handle = limit(
          () async {
            attempts++;
            return 'success';
          },
          retry: RetrySimple(maxAttempts: 3),
        );

        final result = await handle;
        expect(result, equals('success'));
        expect(attempts, equals(1));
      });
    });

    group('RetryFixed', () {
      test('should retry with fixed delay', () async {
        final limit = fLimit(1);
        int attempts = 0;
        final times = <DateTime>[];

        final handle = limit(
          () async {
            attempts++;
            times.add(DateTime.now());
            if (attempts < 3) {
              throw Exception('Not yet');
            }
            return 'success';
          },
          retry: RetryFixed(
            maxAttempts: 3,
            delay: Duration(milliseconds: 50),
          ),
        );

        final result = await handle;
        expect(result, equals('success'));
        expect(attempts, equals(3));

        // Check delays between attempts
        if (times.length >= 2) {
          final delay1 = times[1].difference(times[0]);
          expect(delay1.inMilliseconds, greaterThanOrEqualTo(40));
        }
      });
    });

    group('RetryExponential', () {
      test('should retry with exponential backoff', () async {
        final limit = fLimit(1);
        int attempts = 0;

        final handle = limit(
          () async {
            attempts++;
            if (attempts < 4) {
              throw Exception('Not yet');
            }
            return 'success';
          },
          retry: RetryExponential(
            maxAttempts: 4,
            baseDelay: Duration(milliseconds: 10),
            multiplier: 2.0,
          ),
        );

        final result = await handle;
        expect(result, equals('success'));
        expect(attempts, equals(4));
      });

      test('should cap at maxDelay', () async {
        final policy = RetryExponential(
          maxAttempts: 10,
          baseDelay: Duration(seconds: 1),
          multiplier: 10.0,
          maxDelay: Duration(seconds: 5),
        );

        // High attempt number should still be capped
        final delay = policy.nextDelay(5, Exception('test'), StackTrace.empty);
        expect(delay!.inSeconds, lessThanOrEqualTo(5));
      });
    });

    group('RetryWithJitter', () {
      test('should add jitter to delay', () {
        final inner = RetryFixed(
          maxAttempts: 3,
          delay: Duration(milliseconds: 100),
        );
        final jittered = RetryWithJitter(inner, jitterFactor: 0.5);

        // Get multiple delays and check they vary
        final delays = <int>[];
        for (int i = 0; i < 10; i++) {
          final delay =
              jittered.nextDelay(0, Exception('test'), StackTrace.empty);
          if (delay != null) {
            delays.add(delay.inMilliseconds);
          }
        }

        // Delays should vary (not all the same)
        expect(delays.toSet().length, greaterThan(1));

        // All delays should be within expected range (100ms ± 50%)
        for (final d in delays) {
          expect(d, greaterThanOrEqualTo(50));
          expect(d, lessThanOrEqualTo(150));
        }
      });

      test('should delegate shouldRetry to inner policy', () {
        final inner = RetrySimple(maxAttempts: 3);
        final jittered = RetryWithJitter(inner);

        expect(jittered.shouldRetry(0, Exception('test'), StackTrace.empty),
            isTrue);
        expect(jittered.shouldRetry(1, Exception('test'), StackTrace.empty),
            isTrue);
        expect(jittered.shouldRetry(2, Exception('test'), StackTrace.empty),
            isFalse);
      });
    });
  });

  group('Retry with FLimit', () {
    test('should work with concurrency limit', () async {
      final limit = fLimit(2);
      int activeCount = 0;
      int maxActiveCount = 0;

      final handles = List.generate(3, (i) {
        int attempts = 0;
        return limit(
          () async {
            activeCount++;
            if (activeCount > maxActiveCount) maxActiveCount = activeCount;
            await Future.delayed(Duration(milliseconds: 10));
            attempts++;
            if (attempts < 2) {
              activeCount--;
              throw Exception('Retry needed');
            }
            activeCount--;
            return i;
          },
          retry: RetrySimple(maxAttempts: 2),
        );
      });

      final results = await Future.wait(handles);
      expect(results, equals([0, 1, 2]));
      expect(maxActiveCount, lessThanOrEqualTo(2));
    });

    test('should work with priority queue', () async {
      final limit = fLimit(1, queueStrategy: QueueStrategy.priority);
      final executionOrder = <int>[];

      // Start blocking task
      limit(() async {
        await Future.delayed(Duration(milliseconds: 30));
      });

      await Future.delayed(Duration(milliseconds: 10));

      final handles = [
        limit(
          () async {
            executionOrder.add(1);
            return 1;
          },
          priority: 1,
          retry: RetrySimple(maxAttempts: 1),
        ),
        limit(
          () async {
            executionOrder.add(10);
            return 10;
          },
          priority: 10,
          retry: RetrySimple(maxAttempts: 1),
        ),
      ];

      await Future.wait(handles);

      // Higher priority should execute first
      expect(executionOrder, equals([10, 1]));
    });

    test('should work with timeout', () async {
      final limit = fLimit(1);
      int attempts = 0;

      final handle = limit(
        () async {
          attempts++;
          if (attempts == 1) {
            throw Exception('First attempt fails');
          }
          return 'success';
        },
        timeout: Duration(seconds: 1),
        retry: RetrySimple(maxAttempts: 2),
      );

      final result = await handle;
      expect(result, equals('success'));
      expect(attempts, equals(2));
    });
  });

  group('Custom RetryPolicy', () {
    test('should allow custom retry logic', () async {
      final limit = fLimit(1);
      int attempts = 0;

      // Custom policy that only retries on specific errors
      final customPolicy = _CustomRetryPolicy(
        maxAttempts: 3,
        shouldRetryError: (error) => error.toString().contains('can-retry'),
      );

      final handle = limit(
        () async {
          attempts++;
          if (attempts == 1) {
            throw Exception('can-retry this error');
          }
          return 'success';
        },
        retry: customPolicy,
      );

      final result = await handle;
      expect(result, equals('success'));
      expect(attempts, equals(2));
    });

    test('should not retry on non-retryable errors', () async {
      final limit = fLimit(1);
      int attempts = 0;

      final customPolicy = _CustomRetryPolicy(
        maxAttempts: 3,
        shouldRetryError: (error) => error.toString().contains('can-retry'),
      );

      final handle = limit(
        () async {
          attempts++;
          throw Exception('fatal error');
        },
        retry: customPolicy,
      );

      expect(handle, throwsException);
      try {
        await handle;
      } catch (_) {}
      expect(attempts, equals(1)); // No retry
    });
  });
}

/// Custom retry policy that only retries specific errors
class _CustomRetryPolicy extends RetryPolicy {
  final int maxAttempts;
  final bool Function(Object error) shouldRetryError;

  _CustomRetryPolicy({
    required this.maxAttempts,
    required this.shouldRetryError,
  });

  @override
  bool shouldRetry(int attempt, Object error, StackTrace stackTrace) {
    return attempt < maxAttempts - 1 && shouldRetryError(error);
  }

  @override
  Duration? nextDelay(int attempt, Object error, StackTrace stackTrace) {
    return Duration(milliseconds: 10);
  }
}
