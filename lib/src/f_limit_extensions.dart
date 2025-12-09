import 'dart:async';

import 'f_limit_base.dart';

/// General extensions for [FLimit]
extension FLimitExtensions on FLimit {
  /// Maps the [items] to futures using the [mapper] function, respecting the concurrency limit.
  ///
  /// Returns a Future that completes with a list of results in the same order as [items].
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
  Future<void> get onIdle {
    if (activeCount == 0 && pendingCount == 0) {
      return Future.value();
    }

    final completer = Completer<void>();
    // This is a bit of a hack since FLimit doesn't expose a stream of changes.
    // We can poll or just use the current task completion mechanism if we could hook into it.
    // Since we can't easily hook into internal state changes without modifying FLimit base,
    // we might need to add a listener or use a low-priority task to signal idle?
    // Actually, simply scheduling a low priority task might ensure it runs after others?
    // No, priority queue impacts order.

    // Better approach: Since we are adding this as an extension, we can't modify FLimit state easily to notify.
    // But we can check periodically or add a "barrier" task if we assume FIFO/Priority correct behavior?
    // "onIdle" implies waiting for *current* workload to finish.

    // A simple robust way without modifying FLimit internals too much is to poll.
    // BUT polling is inefficient.
    // Let's modify FLimit base to support this properly if needed, but for now as an extension:
    // We can submit a task that checks if we are idle? No that takes up a slot.

    // Let's implement it by checking periodically for now, as it's an extension.
    // Or better: we can wrap the task execution in FLimit if we could... but we can't.

    // Actually, if we look at FLimit implementation, `_activeCount` and `_queue` are private.
    // `activeCount` and `pendingCount` are public getters.

    Timer.periodic(Duration(milliseconds: 10), (timer) {
      if (activeCount == 0 && pendingCount == 0) {
        timer.cancel();
        completer.complete();
      }
    });

    return completer.future;
  }
}
