import 'dart:async';

import 'f_limit_base.dart';
import 'retry.dart';

/// Extension methods for [FLimit]
///
/// Provides additional functionality like concurrent mapping, filtering,
/// iteration, and idle detection.
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
    Future<Result> Function(Item item) mapper, {
    int priority = 0,
    Duration? timeout,
    RetryPolicy? retry,
    TaskTimeouts? timeouts,
  }) {
    final futures = items.map((item) {
      return this(
        () => mapper(item),
        priority: priority,
        timeout: timeout,
        retry: retry,
        timeouts: timeouts,
      ).future;
    }).toList();
    return Future.wait(futures);
  }

  /// Maps [items] and captures both successes and failures without throwing.
  Future<List<SettledResult<Result>>> mapSettled<Item, Result>(
    Iterable<Item> items,
    Future<Result> Function(Item item) mapper, {
    int priority = 0,
    Duration? timeout,
    RetryPolicy? retry,
    TaskTimeouts? timeouts,
  }) {
    final handles = items.map((item) {
      return this(
        () => mapper(item),
        priority: priority,
        timeout: timeout,
        retry: retry,
        timeouts: timeouts,
      );
    }).toList();

    return Future.wait(handles.map((handle) async {
      try {
        return SettledResult<Result>.success(await handle);
      } catch (error, stackTrace) {
        final status = error is CanceledException
            ? TaskStatus.canceled
            : TaskStatus.failed;
        return SettledResult<Result>.failure(
          error,
          stackTrace,
          status: status,
        );
      }
    }));
  }

  /// Executes [action] for each item in [items] concurrently with the concurrency limit.
  ///
  /// Unlike [map], this method doesn't collect results and is useful for
  /// side-effect operations.
  ///
  /// Example:
  /// ```dart
  /// final limit = fLimit(2);
  /// final items = [1, 2, 3, 4, 5];
  ///
  /// await limit.forEach(items, (item) async {
  ///   await processItem(item);
  /// });
  /// ```
  Future<void> forEach<Item>(
    Iterable<Item> items,
    Future<void> Function(Item item) action, {
    int priority = 0,
    Duration? timeout,
    RetryPolicy? retry,
    TaskTimeouts? timeouts,
  }) {
    final futures = items.map((item) {
      return this(
        () => action(item),
        priority: priority,
        timeout: timeout,
        retry: retry,
        timeouts: timeouts,
      ).future;
    }).toList();
    return Future.wait(futures);
  }

  /// Executes [action] for each item and returns settled outcomes.
  Future<List<SettledResult<void>>> forEachSettled<Item>(
    Iterable<Item> items,
    Future<void> Function(Item item) action, {
    int priority = 0,
    Duration? timeout,
    RetryPolicy? retry,
    TaskTimeouts? timeouts,
  }) {
    final handles = items.map((item) {
      return this(
        () => action(item),
        priority: priority,
        timeout: timeout,
        retry: retry,
        timeouts: timeouts,
      );
    }).toList();

    return Future.wait(handles.map((handle) async {
      try {
        await handle;
        return const SettledResult<void>.success(null);
      } catch (error, stackTrace) {
        final status = error is CanceledException
            ? TaskStatus.canceled
            : TaskStatus.failed;
        return SettledResult<void>.failure(
          error,
          stackTrace,
          status: status,
        );
      }
    }));
  }

  /// Filters [items] concurrently using the [predicate] function.
  ///
  /// Returns a Future that completes with a list of items for which
  /// [predicate] returned `true`. The order is preserved.
  ///
  /// Example:
  /// ```dart
  /// final limit = fLimit(2);
  /// final items = [1, 2, 3, 4, 5];
  ///
  /// final evens = await limit.filter(items, (item) async {
  ///   return item % 2 == 0;
  /// });
  /// // evens = [2, 4]
  /// ```
  Future<List<Item>> filter<Item>(
    Iterable<Item> items,
    Future<bool> Function(Item item) predicate, {
    int priority = 0,
    Duration? timeout,
    RetryPolicy? retry,
    TaskTimeouts? timeouts,
  }) async {
    final itemList = items.toList();
    final results = await Future.wait(
      itemList.map((item) {
        return this(
          () => predicate(item),
          priority: priority,
          timeout: timeout,
          retry: retry,
          timeouts: timeouts,
        ).future;
      }),
    );

    return [
      for (var i = 0; i < itemList.length; i++)
        if (results[i]) itemList[i]
    ];
  }

  /// Executes tasks and collects results with their indices.
  ///
  /// Useful when you need to know which result corresponds to which input.
  ///
  /// Example:
  /// ```dart
  /// final limit = fLimit(2);
  /// final items = ['a', 'b', 'c'];
  ///
  /// final results = await limit.mapIndexed(items, (index, item) async {
  ///   return '$index:$item';
  /// });
  /// // results = ['0:a', '1:b', '2:c']
  /// ```
  Future<List<Result>> mapIndexed<Item, Result>(
    Iterable<Item> items,
    Future<Result> Function(int index, Item item) mapper, {
    int priority = 0,
    Duration? timeout,
    RetryPolicy? retry,
    TaskTimeouts? timeouts,
  }) {
    final itemList = items.toList();
    final futures = itemList.asMap().entries.map((entry) {
      return this(
        () => mapper(entry.key, entry.value),
        priority: priority,
        timeout: timeout,
        retry: retry,
        timeouts: timeouts,
      ).future;
    }).toList();
    return Future.wait(futures);
  }

  /// Reduces [items] to a single value using [combine] function.
  ///
  /// Items are processed in order, but the reduction happens sequentially
  /// after all items are processed.
  ///
  /// Example:
  /// ```dart
  /// final limit = fLimit(2);
  /// final items = [1, 2, 3, 4, 5];
  ///
  /// final sum = await limit.reduce(items, (a, b) async => a + b);
  /// // sum = 15
  /// ```
  Future<Item> reduce<Item>(
    Iterable<Item> items,
    Future<Item> Function(Item a, Item b) combine, {
    int priority = 0,
    Duration? timeout,
    RetryPolicy? retry,
    TaskTimeouts? timeouts,
  }) async {
    final itemList = items.toList();
    if (itemList.isEmpty) {
      throw StateError('No element');
    }

    var accumulator = itemList.first;
    for (var i = 1; i < itemList.length; i++) {
      accumulator = await this(
        () => combine(accumulator, itemList[i]),
        priority: priority,
        timeout: timeout,
        retry: retry,
        timeouts: timeouts,
      ).future;
    }
    return accumulator;
  }
}
