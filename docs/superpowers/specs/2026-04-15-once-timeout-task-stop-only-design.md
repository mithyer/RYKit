# OnceTimeoutTask Stop-Only Design

- Date: 2026-04-15
- Repo: `RYKit`
- Authoring mode: Brainstorming -> Design approved by user

## 1. Goal

Remove the cancel concept from `OnceTimeoutTask` and `OnceTimeoutTaskQueue`. All task interruption and queue-wide shutdown behavior should use stop semantics.

## 2. Scope

In scope:

- Remove `DoneType.cancel`.
- Remove public `OnceTimeoutTask.cancel()`.
- Remove internal cancel helpers such as `cancelFromQueue` and `transitionToCancel`.
- Rename `OnceTimeoutTaskQueue.cancelAll(where:)` to `stopAll(where:)`.
- Make task `stop` non-optional again, with a default immediate-stop implementation.
- Replace all TimeoutTask tests and README examples that refer to cancel.

Out of scope:

- Changing priority ordering.
- Changing `taskDidFinish` payload shape.
- Changing execution timeout behavior.
- Changing `waitingRestart(stopped:)` state.
- Keeping deprecated cancel aliases.

## 3. Public Task API

`DoneType` becomes:

```swift
public enum DoneType {
    case executionTimeout
    case stop
    case completed(Result<T, E>)
}
```

Callback initializer becomes:

```swift
public init(
    flag: String,
    executionTimeoutInterval: DispatchTimeInterval?,
    stopTimeoutInterval: DispatchTimeInterval?,
    execute: @escaping (@escaping Completed) -> Void,
    stopWhenExecuting: @escaping StopWhenExecuting = { stopped in stopped() }
)
```

Async initializer becomes:

```swift
public convenience init(
    flag: String,
    executionTimeoutInterval: DispatchTimeInterval?,
    stopTimeoutInterval: DispatchTimeInterval?,
    execute: @escaping () async -> Result<T, E>,
    stopWhenExecuting: @escaping () async -> Void = {}
)
```

`public func stop()` remains the only public interruption method.

## 4. Stop Defaults

The default callback stop is:

```swift
{ stopped in stopped() }
```

The default async stop is:

```swift
{}
```

This means a task with no custom cleanup is still stoppable, and queue stop operations can continue immediately.

The typealias is also renamed for clarity:

```swift
public typealias StopWhenExecuting = (@escaping Stopped) -> Void
```

## 5. Queue API

`OnceTimeoutTaskQueue` replaces:

```swift
public func cancelAll(where block: ((OnceTimeoutTask<T, E>) -> Bool)? = nil)
```

with:

```swift
public func stopAll(where block: ((OnceTimeoutTask<T, E>) -> Bool)? = nil)
```

There is no deprecated `cancelAll` alias.

## 6. Queue Stop Semantics

`stopAll(where:)` behavior:

- Waiting tasks matched by `block` move directly to `.done(.stop)` and emit `TaskFinishEvent(doneType: .stop)`.
- The current task matched by `block` is stopped through the normal stop request path and emits `.stop` after `stopped()` or stop timeout.
- A task in `.waitingRestart(stopped: false)` matched by `block` abandons restart intent, ultimately moves to `.done(.stop)`, and emits `.stop` only after the current stop cleanup finishes.
- A task in `.waitingRestart(stopped: true)` that is already back in the waiting list moves directly to `.done(.stop)` and emits `.stop`.
- Tasks not matched by `block` remain in queue ownership.

`stopAll(where:)` still publishes `taskDidFinish` outside queue locks.

## 7. Preemption Semantics

Existing preemption behavior remains stop-based:

- `.waitCurrentCompletion`: no stop.
- `.stopCurrentAndDiscard`: final stop and discard.
- `.stopCurrentAndRequeue`: restart stop with `waitingRestart(stopped:)`.

No preemption path produces `.cancel`.

## 8. Testing Requirements

Tests must cover:

1. `DoneType.cancel` is gone from TimeoutTask tests.
2. Public `cancel()` is gone from TimeoutTask tests.
3. `stopAll(where:)` stops waiting tasks and emits `.stop`.
4. `stopAll(where:)` stops the current task and waits for `stopped()` before emitting `.stop`.
5. `stopAll(where:)` during `.waitingRestart(stopped: false)` emits `.stop` after `stopped()`.
6. `stopAll(where:)` with a filter leaves unmatched tasks queued/running.
7. Default callback stop lets public `stop()` complete immediately.
8. Default async stop lets queue stop operations complete immediately.
9. Existing `.stopCurrentAndDiscard` and `.stopCurrentAndRequeue` tests still pass with `.stop`.

Verification should include:

```bash
rtk xcodebuild test -project Project/RYKit.xcodeproj -scheme RYKitTests -destination 'platform=macOS' -only-testing:RYKitTests/OnceTimeoutTaskTests BUILD_LIBRARY_FOR_DISTRIBUTION=NO
rtk xcodebuild test -project Project/RYKit.xcodeproj -scheme RYKitTests -destination 'platform=macOS' -only-testing:RYKitTests/OnceTimeoutTaskQueueTests BUILD_LIBRARY_FOR_DISTRIBUTION=NO
rtk xcodebuild test -project Project/RYKit.xcodeproj -scheme RYKitTests -destination 'platform=macOS' BUILD_LIBRARY_FOR_DISTRIBUTION=NO
rtk swift build
```
