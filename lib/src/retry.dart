import 'dart:async';
import 'dart:math';

/// Abstract interface for retry policies
///
/// Retry policies determine when and how to retry failed tasks.
/// Implement this interface to create custom retry strategies.
///
/// Example:
/// ```dart
/// class MyRetryPolicy extends RetryPolicy {
///   @override
///   bool shouldRetry(int attempt, Object error, StackTrace stackTrace) {
///     return attempt < 3 && error is NetworkException;
///   }
///
///   @override
///   Duration? nextDelay(int attempt, Object error, StackTrace stackTrace) {
///     return Duration(seconds: attempt);
///   }
/// }
/// ```
abstract class RetryPolicy {
  /// Creates a retry policy
  const RetryPolicy();

  /// Whether the task should be retried
  ///
  /// [attempt] is the current attempt number (0-based for first attempt).
  /// [error] is the error that caused the failure.
  /// [stackTrace] is the stack trace of the error.
  bool shouldRetry(int attempt, Object error, StackTrace stackTrace);

  /// Returns the delay before the next retry, or null for immediate retry
  ///
  /// [attempt] is the current attempt number (0-based for first attempt).
  /// [error] is the error that caused the failure.
  /// [stackTrace] is the stack trace of the error.
  Duration? nextDelay(int attempt, Object error, StackTrace stackTrace);
}

int _validateMaxAttempts(int value) {
  if (value < 1) {
    throw ArgumentError.value(value, 'maxAttempts', 'Must be at least 1.');
  }
  return value;
}

Duration _validateNonNegativeDuration(Duration value, String name) {
  if (value.isNegative) {
    throw ArgumentError.value(value, name, 'Must not be negative.');
  }
  return value;
}

double _validatePositiveFinite(double value, String name) {
  if (!value.isFinite || value <= 0) {
    throw ArgumentError.value(value, name, 'Must be a positive finite number.');
  }
  return value;
}

double _validateRange(
  double value,
  String name, {
  required double min,
  required double max,
}) {
  if (value.isNaN || value < min || value > max) {
    throw ArgumentError.value(
      value,
      name,
      'Must be between $min and $max inclusive.',
    );
  }
  return value;
}

/// Simple retry policy: retry up to a maximum number of attempts with no delay
///
/// Example:
/// ```dart
/// final limit = fLimit(2);
///
/// await limit(
///   () => fetchData(),
///   retry: RetrySimple(maxAttempts: 3),
/// );
/// ```
class RetrySimple extends RetryPolicy {
  /// Maximum number of attempts (including the initial attempt)
  final int maxAttempts;

  /// Creates a simple retry policy
  ///
  /// [maxAttempts] is the total number of attempts (initial + retries).
  /// For example, maxAttempts: 3 means 1 initial attempt + 2 retries.
  RetrySimple({required int maxAttempts})
      : maxAttempts = _validateMaxAttempts(maxAttempts);

  @override
  bool shouldRetry(int attempt, Object error, StackTrace stackTrace) {
    return attempt < maxAttempts - 1;
  }

  @override
  Duration? nextDelay(int attempt, Object error, StackTrace stackTrace) {
    return null; // No delay between retries
  }
}

/// Fixed delay retry policy: retry with a constant delay between attempts
///
/// Example:
/// ```dart
/// final limit = fLimit(2);
///
/// await limit(
///   () => fetchData(),
///   retry: RetryFixed(
///     maxAttempts: 3,
///     delay: Duration(seconds: 2),
///   ),
/// );
/// ```
class RetryFixed extends RetryPolicy {
  /// Maximum number of attempts (including the initial attempt)
  final int maxAttempts;

  /// Fixed delay between retry attempts
  final Duration delay;

  /// Creates a fixed delay retry policy
  ///
  /// [maxAttempts] is the total number of attempts (initial + retries).
  /// [delay] is the constant delay between each retry.
  RetryFixed({
    required int maxAttempts,
    required Duration delay,
  })  : maxAttempts = _validateMaxAttempts(maxAttempts),
        delay = _validateNonNegativeDuration(delay, 'delay');

  @override
  bool shouldRetry(int attempt, Object error, StackTrace stackTrace) {
    return attempt < maxAttempts - 1;
  }

  @override
  Duration? nextDelay(int attempt, Object error, StackTrace stackTrace) {
    return delay;
  }
}

/// Exponential backoff retry policy: delay increases exponentially with each attempt
///
/// The delay is calculated as: baseDelay * (multiplier ^ attempt)
///
/// Example:
/// ```dart
/// final limit = fLimit(2);
///
/// await limit(
///   () => fetchData(),
///   retry: RetryExponential(
///     maxAttempts: 5,
///     baseDelay: Duration(seconds: 1),
///     multiplier: 2.0,
///     maxDelay: Duration(seconds: 30),
///   ),
/// );
/// // Delays: 1s, 2s, 4s, 8s (capped at maxDelay)
/// ```
class RetryExponential extends RetryPolicy {
  /// Maximum number of attempts (including the initial attempt)
  final int maxAttempts;

  /// Base delay for the first retry
  final Duration baseDelay;

  /// Multiplier applied to delay for each subsequent retry
  final double multiplier;

  /// Maximum delay cap to prevent excessive waits
  final Duration maxDelay;

  /// Creates an exponential backoff retry policy
  ///
  /// [maxAttempts] is the total number of attempts (initial + retries).
  /// [baseDelay] is the delay for the first retry.
  /// [multiplier] is applied to the delay for each subsequent retry (default: 2.0).
  /// [maxDelay] caps the maximum delay (default: 1 minute).
  RetryExponential({
    required int maxAttempts,
    required Duration baseDelay,
    double multiplier = 2.0,
    Duration maxDelay = const Duration(minutes: 1),
  })  : maxAttempts = _validateMaxAttempts(maxAttempts),
        baseDelay = _validateNonNegativeDuration(baseDelay, 'baseDelay'),
        multiplier = _validatePositiveFinite(multiplier, 'multiplier'),
        maxDelay = _validateNonNegativeDuration(maxDelay, 'maxDelay');

  @override
  bool shouldRetry(int attempt, Object error, StackTrace stackTrace) {
    return attempt < maxAttempts - 1;
  }

  @override
  Duration? nextDelay(int attempt, Object error, StackTrace stackTrace) {
    final delayMs = baseDelay.inMilliseconds * (multiplier.pow(attempt));
    final cappedMs = delayMs.round().clamp(0, maxDelay.inMilliseconds);
    return Duration(milliseconds: cappedMs);
  }
}

/// Decorator that adds random jitter to any retry policy
///
/// Jitter helps prevent thundering herd problems when multiple clients
/// retry simultaneously.
///
/// Example:
/// ```dart
/// final limit = fLimit(2);
///
/// await limit(
///   () => fetchData(),
///   retry: RetryWithJitter(
///     RetryExponential(
///       maxAttempts: 3,
///       baseDelay: Duration(seconds: 1),
///     ),
///     jitterFactor: 0.5,
///   ),
/// );
/// // With jitterFactor 0.5, a 2s delay becomes 1s-3s (2s ± 50%)
/// ```
class RetryWithJitter extends RetryPolicy {
  /// The underlying retry policy to decorate
  final RetryPolicy inner;

  /// Jitter factor (0.0 to 1.0)
  ///
  /// A factor of 0.5 means the delay can vary by ±50%.
  /// For example, a 2s delay becomes 1s-3s.
  final double jitterFactor;

  final Random _random;

  /// Creates a jittered retry policy
  ///
  /// [inner] is the underlying retry policy to add jitter to.
  /// [jitterFactor] controls the amount of random variation (0.0 to 1.0).
  RetryWithJitter(this.inner, {double jitterFactor = 0.5})
      : jitterFactor = _validateRange(
          jitterFactor,
          'jitterFactor',
          min: 0.0,
          max: 1.0,
        ),
        _random = Random();

  @override
  bool shouldRetry(int attempt, Object error, StackTrace stackTrace) {
    return inner.shouldRetry(attempt, error, stackTrace);
  }

  @override
  Duration? nextDelay(int attempt, Object error, StackTrace stackTrace) {
    final baseDelay = inner.nextDelay(attempt, error, stackTrace);
    if (baseDelay == null) return null;

    // Calculate jitter: baseDelay * (1 - jitterFactor + random * 2 * jitterFactor)
    final jitterRange = baseDelay.inMilliseconds * jitterFactor * 2;
    final jitter = _random.nextDouble() * jitterRange -
        (baseDelay.inMilliseconds * jitterFactor);
    final jitteredMs = (baseDelay.inMilliseconds + jitter)
        .round()
        .clamp(0, double.maxFinite.toInt());

    return Duration(milliseconds: jitteredMs);
  }
}

/// Helper function to execute a function with a retry policy.
///
/// This can be used directly when retry behavior is needed outside of [FLimit].
Future<T> executeWithRetry<T>(
  Future<T> Function() function,
  RetryPolicy retryPolicy,
) async {
  int attempt = 0;

  while (true) {
    try {
      return await function();
    } catch (error, stackTrace) {
      if (!retryPolicy.shouldRetry(attempt, error, stackTrace)) {
        rethrow;
      }

      final delay = retryPolicy.nextDelay(attempt, error, stackTrace);
      if (delay != null) {
        await Future.delayed(delay);
      }

      attempt++;
    }
  }
}

/// Extension on double for power calculation
extension _DoublePow on double {
  double pow(int exponent) {
    if (exponent == 0) return 1.0;
    if (exponent == 1) return this;
    double result = 1.0;
    for (int i = 0; i < exponent; i++) {
      result *= this;
    }
    return result;
  }
}
