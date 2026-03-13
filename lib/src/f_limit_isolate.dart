import 'dart:async';
import 'dart:isolate';

import 'f_limit_base.dart';
import 'retry.dart';

/// Extension on [FLimit] to support running tasks in a separate isolate
///
/// This extension provides the [isolate] method which allows running
/// computationally heavy tasks in a separate isolate while respecting
/// the concurrency limit.
///
/// Example:
/// ```dart
/// final limit = fLimit(2);
///
/// // Run heavy computation in isolate
/// final result = await limit.isolate(() {
///   int sum = 0;
///   for (int i = 0; i < 1000000; i++) {
///     sum += i;
///   }
///   return sum;
/// });
///
/// // With priority
/// await limit.isolate(() => heavyTask(), priority: 10);
/// ```
extension FLimitIsolate on FLimit {
  /// Executes a computation in a separate isolate with concurrency limit
  ///
  /// This method wraps [Isolate.run] and executes it through the [FLimit] instance.
  /// The computation runs in a separate isolate, preventing blocking of the main
  /// thread, while still respecting the concurrency limit.
  ///
  /// The [computation] function must be a top-level function, a static method,
  /// or a closure that captures only sendable state from the current isolate.
  ///
  /// [priority] can be used to set the priority of the task if the queue strategy
  /// supports it. Higher values execute first. Defaults to 0.
  ///
  /// [timeout] if specified, the task will fail with [TimeoutException]
  /// if it doesn't complete within the given duration.
  /// This is an alias for [timeouts].run.
  ///
  /// [timeouts] provides queue/run/total timeout control. If [timeouts].run is
  /// specified, do not also pass [timeout].
  ///
  /// [retry] if specified, failed tasks will be retried according to the policy.
  /// Note: Retry with isolate may have limited usefulness since the computation
  /// runs in a separate isolate and errors may not be easily recoverable.
  ///
  /// Returns a [TaskHandle] that can be used to cancel the task or await the result.
  ///
  /// Example:
  /// ```dart
  /// int calculateSquare(int n) => n * n;
  ///
  /// void main() async {
  ///   final limit = fLimit(2);
  ///
  ///   final result = await limit.isolate(() => calculateSquare(42));
  ///   print(result);
  /// }
  /// ```
  ///
  /// See also:
  /// - [Isolate.run] for more information about isolate constraints
  TaskHandle<T> isolate<T>(
    FutureOr<T> Function() computation, {
    int priority = 0,
    Duration? timeout,
    TaskTimeouts? timeouts,
    RetryPolicy? retry,
  }) {
    return this(
      () => Isolate.run(computation),
      priority: priority,
      timeout: timeout,
      timeouts: timeouts,
      retry: retry,
    );
  }
}
