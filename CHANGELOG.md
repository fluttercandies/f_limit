## 2.0.0

* `call()` and `isolate()` now return `TaskHandle<T>` instead of `Future<T>`, while existing `await` and `Future.wait` usage still works because `TaskHandle<T>` implements `Future<T>`
* Add `TaskHandle` with task id, status, cancellation, and direct await support
* Add pause/resume support with `pause()`, `resume()`, and `isPaused`
* Move `onIdle` from extension API to a direct getter on `FLimit`
* Add timeout support for tasks, including `TaskTimeouts` and `TimeoutStage`
* Add retry policies: `RetrySimple`, `RetryFixed`, `RetryExponential`, and `RetryWithJitter`
* Add limiter lifecycle APIs: `close()`, `dispose()`, `isClosed`, `isEmpty`, and `isBusy`
* Add extension methods: `filter`, `forEach`, `mapIndexed`, `reduce`, `mapSettled`, and `forEachSettled`
* Fix cancellation race, queue clearing behavior, `onIdle` completion, priority queue removal ordering, and timeout concurrency semantics
* Improve `onIdle` efficiency and priority queue heap implementation

---

## 1.2.0

* Add `Alternating` queue strategy - takes from head, tail, head, tail...
* Add `Random` queue strategy - randomly selects task from queue
* Add comprehensive dart documentation with examples
* Refactor README to concise checklist style
* Update package description

## 1.1.0

* Add isolate support with `isolate` extension method
* Add `map` and `onIdle` extension methods

## 1.0.1

* Update SDK constraints in pubspec.yaml


## 1.0.0

* Initial release with basic functionality
