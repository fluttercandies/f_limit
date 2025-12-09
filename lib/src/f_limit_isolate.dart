import 'dart:async';
import 'dart:isolate';

import 'f_limit_base.dart';

/// Extension on [FLimit] to support running tasks in a separate isolate
extension FLimitIsolate on FLimit {
  /// Executes a computation in a separate isolate with concurrency limit
  ///
  /// This method wraps [Isolate.run] and executes it through the [FLimit] instance.
  /// The [computation] function must be a top-level function or a static method,
  /// or a closure that doesn't capture any state from the current isolate.
  ///
  /// [priority] can be used to set the priority of the task if the queue strategy
  /// supports it.
  Future<T> isolate<T>(FutureOr<T> Function() computation, {int priority = 0}) {
    return this(() => Isolate.run(computation), priority: priority);
  }
}
