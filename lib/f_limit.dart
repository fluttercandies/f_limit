/// A Dart implementation of p-limit for controlling concurrency
///
/// This library provides utilities to limit the number of concurrent async operations.
/// It's useful for controlling resource usage and preventing overwhelming external services.
///
/// Features:
/// - Concurrency limiting with configurable limits
/// - Multiple queue strategies: FIFO, LIFO, Priority, Alternating, Random
/// - Task cancellation support via [TaskHandle]
/// - Timeout support for individual tasks
/// - Retry policies with exponential backoff and jitter
/// - Pause/resume functionality
/// - Isolate support for CPU-intensive tasks
/// - Extension methods for concurrent mapping, filtering, and iteration
library f_limit;

export 'src/f_limit_base.dart';
export 'src/f_limit_isolate.dart';
export 'src/f_limit_extensions.dart';
export 'src/retry.dart';
