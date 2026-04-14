# OnceTimeoutTask Optional Stop And Timeout Design

- Date: 2026-04-14
- Repo: `RYKit`
- Authoring mode: Brainstorming -> Design approved by user

## 1. Goal

Allow `OnceTimeoutTask` callers to omit stop handling and timeout intervals. A task with `stop == nil` is not stoppable; a `nil` timeout means that timeout is disabled.

## 2. Scope

In scope:

- Make `executionTimeoutInterval` optional.
- Make `stopTimeoutInterval` optional.
- Make callback initializer `stop` optional.
- Make async initializer `stop` optional.
- Treat non-stoppable tasks as not preemptable by queue stop strategies.
- Update tests and README examples.

Out of scope:

- Changing priority ordering.
- Changing `taskDidFinish` payloads.
- Adding external state observers.
- Adding a separate cancellation mechanism for non-stoppable tasks.

## 3. Public API

Callback initializer becomes:

```swift
public init(
    flag: String,
    executionTimeoutInterval: DispatchTimeInterval?,
    stopTimeoutInterval: DispatchTimeInterval?,
    execute: @escaping (@escaping Completed) -> Void,
    stop: Stop?
)
```

Async initializer becomes:

```swift
public convenience init(
    flag: String,
    executionTimeoutInterval: DispatchTimeInterval?,
    stopTimeoutInterval: DispatchTimeInterval?,
    execute: @escaping () async -> Result<T, E>,
    stop: (() async -> Void)?
)
```

Callers must pass `nil` explicitly when they want no stop handling. There is no default stop implementation.

## 4. Execution Timeout Semantics

`executionTimeoutInterval == nil` disables execution timeout scheduling.

State behavior:

- If the task completes, it moves to `.done(.completed(result))`.
- If execution timeout is nil and the task never completes, it remains `.executing` until completion, cancel, or a valid stop.
- `.done(.executionTimeout)` can occur only when `executionTimeoutInterval` is non-nil.

## 5. Stop Timeout Semantics

`stopTimeoutInterval == nil` disables stop timeout scheduling.

State behavior:

- If a stoppable task is stopped, queue ownership waits until the task calls `stopped()`.
- If `stopTimeoutInterval` is non-nil, the queue waits for `stopped()` or timeout, whichever happens first.
- If `stopTimeoutInterval == nil` and the stop closure never calls `stopped()`, the queue waits indefinitely.

This replaces the previous need to use `.never` for no stop timeout. `.never` can still be accepted because it is a valid `DispatchTimeInterval`, but `nil` is the preferred “no timeout” spelling.

## 6. Non-Stoppable Task Semantics

`stop == nil` means the task cannot be stopped.

Public `task.stop()` behavior:

- Does nothing.
- Does not change state.
- Does not emit `onDone`.
- Does not call any stop closure.

Queue preemption behavior:

- If a high-priority task is added while the current task has `stop == nil`, the effective behavior is `.waitCurrentCompletion`, regardless of configured `PreemptionStrategy`.
- This applies to queue default strategy and per-add strategy overrides.
- The new high-priority task is inserted by priority and waits for the current task to finish.

If the non-stoppable current task also has `executionTimeoutInterval == nil` and never completes, it can hold the queue forever. This is intentional and follows from “cannot be stopped” plus “no execution timeout.”

## 7. Queue Strategy Rules

For stoppable current tasks:

- `.waitCurrentCompletion` remains unchanged.
- `.stopCurrentAndDiscard` uses final-stop flow.
- `.stopCurrentAndRequeue` uses waiting-restart flow.

For non-stoppable current tasks:

```text
any preemption strategy -> waitCurrentCompletion
```

The queue should not attempt `makeStopRequest` or `makeRestartStopRequest` when the current task is non-stoppable.

## 8. Testing Requirements

Tests must cover:

1. `executionTimeoutInterval == nil` does not timeout a non-completing task.
2. `stopTimeoutInterval == nil` waits for `stopped()` and does not fallback timeout.
3. Public `stop()` on `stop == nil` leaves state `.executing`.
4. `.stopCurrentAndDiscard` against a non-stoppable current task behaves as wait-current-completion.
5. `.stopCurrentAndRequeue` against a non-stoppable current task behaves as wait-current-completion.
6. Existing stoppable discard/requeue tests still pass.
7. Existing async initializer tests pass with optional async stop.

Verification should include:

```bash
rtk xcodebuild test -project Project/RYKit.xcodeproj -scheme RYKitTests -destination 'platform=macOS' -only-testing:RYKitTests/OnceTimeoutTaskTests BUILD_LIBRARY_FOR_DISTRIBUTION=NO
rtk xcodebuild test -project Project/RYKit.xcodeproj -scheme RYKitTests -destination 'platform=macOS' -only-testing:RYKitTests/OnceTimeoutTaskQueueTests BUILD_LIBRARY_FOR_DISTRIBUTION=NO
rtk xcodebuild test -project Project/RYKit.xcodeproj -scheme RYKitTests -destination 'platform=macOS' BUILD_LIBRARY_FOR_DISTRIBUTION=NO
rtk swift build
```

