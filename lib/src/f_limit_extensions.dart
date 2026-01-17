import 'dart:async';

import 'f_limit_base.dart';

/// Extension methods for [FLimit]
///
/// Provides additional functionality like concurrent mapping and idle detection.
///
/// Example:
/// ```dart
/// final limit = fLimit(2);
///
/// // Map items concurrently
/// final items = [1, 2, 3, 4, 5];
/// final results = await limit.map(items, (i) async => i * 2);
///
/// // Wait for all tasks to complete
/// await limit.onIdle;
/// print('All done!');
/// ```
extension FLimitExtensions on FLimit {
  /// Maps the [items] to futures using the [mapper] function, respecting the concurrency limit.
  ///
  /// All items are mapped concurrently, but the number of simultaneous operations
  /// is limited by the limiter's concurrency setting.
  ///
  /// Returns a Future that completes with a list of results in the same order as [items].
  ///
  /// Example:
  /// ```dart
  /// final limit = fLimit(3);
  /// final urls = ['url1', 'url2', 'url3', 'url4', 'url5'];
  ///
  /// final responses = await limit.map(urls, (url) async {
  ///   return await http.get(url);
  /// });
  /// // responses are in the same order as urls
  /// ```
  Future<List<Result>> map<Item, Result>(
    Iterable<Item> items,
    Future<Result> Function(Item item) mapper,
  ) {
    var futures = <Future<Result>>[];
    for (var item in items) {
      futures.add(this(() => mapper(item)));
    }
    return Future.wait(futures);
  }

  /// Returns a Future that completes when the queue is empty and active count is 0.
  ///
  /// Useful for waiting for all pending tasks to complete before proceeding.
  ///
  /// If the limiter is already idle, returns a completed Future immediately.
  ///
  /// Example:
  /// ```dart
  /// final limit = fLimit(2);
  ///
  /// // Add tasks...
  /// for (int i = 0; i < 10; i++) {
  ///   limit(() async => processItem(i));
  /// }
  ///
  /// // Wait for all to finish
  /// await limit.onIdle;
  /// print('All tasks completed!');
  /// ```
  Future<void> get onIdle {
    if (activeCount == 0 && pendingCount == 0) {
      return Future.value();
    }

    final completer = Completer<void>();

    // Poll until idle
    Timer.periodic(Duration(milliseconds: 10), (timer) {
      if (activeCount == 0 && pendingCount == 0) {
        timer.cancel();
        completer.complete();
      }
    });

    return completer.future;
  }
}
