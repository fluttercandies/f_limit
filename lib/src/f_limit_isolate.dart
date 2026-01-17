import 'dart:async';
import 'dart:isolate';

import 'f_limit_base.dart';

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
  /// or a closure that doesn't capture any non-sendable state from the current
  /// isolate (e.g., no closures, no non-sendable objects).
  ///
  /// [priority] can be used to set the priority of the task if the queue strategy
  /// supports it. Higher values execute first. Defaults to 0.
  ///
  /// Returns a Future that completes with the result of [computation].
  ///
  /// Example:
  /// ```dart
  /// final limit = fLimit(2);
  ///
  /// // Simple computation
  /// final sum = await limit.isolate(() {
  ///   int total = 0;
  ///   for (int i = 0; i < 1000000; i++) {
  ///     total += i;
  ///   }
  ///   return total;
  /// });
  ///
  /// // With priority
  /// await limit.isolate(() {
  ///   return heavyComputation();
  /// }, priority: 10);
  ///
  /// // Using a static function
  /// static int calculate(int n) {
  ///   return n * n;
  /// }
  /// await limit.isolate(() => calculate(42));
  /// ```
  ///
  /// See also:
  /// - [Isolate.run] for more information about isolate constraints
  Future<T> isolate<T>(FutureOr<T> Function() computation, {int priority = 0}) {
    return this(() => Isolate.run(computation), priority: priority);
  }
}
