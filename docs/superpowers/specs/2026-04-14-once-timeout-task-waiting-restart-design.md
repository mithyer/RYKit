# OnceTimeoutTask Waiting Restart State Design

- Date: 2026-04-14
- Repo: `RYKit`
- Authoring mode: Brainstorming -> Design approved by user

## 1. Goal

Add an explicit `waitingRestart(stopped:)` state to `OnceTimeoutTask` so callers can distinguish a task that has never run from a task that was stopped by `OnceTimeoutTaskQueue` and is waiting to be restarted.

## 2. Scope

In scope:

- Add `State.waitingRestart(stopped: Bool)`.
- Add separate internal stop-and-wait semantics for `.stopCurrentAndRequeue`.
- Update queue requeue flow to use `waitingRestart(stopped:)` instead of resetting directly from `.done(.stop)` to `.unstart`.
- Preserve existing finish-event behavior: requeued tasks do not emit `taskDidFinish` for the intermediate stop.
- Update tests for task state, requeue state transitions, and `cancelAll()` while waiting for restart stop completion.

Out of scope:

- Changing public task initializer parameters.
- Changing priority ordering rules.
- Changing `taskDidFinish` payload shape.
- Changing normal public `task.stop()` final-stop behavior.
- Adding a separate public observer API for state changes.

## 3. State Model

`OnceTimeoutTask.State` becomes:

```swift
public enum State {
    case unstart
    case executing
    case waitingRestart(stopped: Bool)
    case done(DoneType)
}
```

State meanings:

- `.unstart`: task has never started and can be executed for the first time.
- `.executing`: task is currently running.
- `.waitingRestart(stopped: false)`: queue has requested stop for a restart, but `stopped()` or `stopTimeoutInterval` has not completed yet.
- `.waitingRestart(stopped: true)`: stop cleanup has completed and the task is waiting in the queue to execute again.
- `.done(...)`: task has left its active lifecycle and will not restart.

## 4. Computed State Semantics

Keep `hasStarted` as historical state:

- `.unstart` returns `false`.
- `.waitingRestart`, `.executing`, and `.done` return `true`.

Keep `isDone` true only for `.done`.

Add internal start/enqueue semantics:

```swift
var canStart: Bool {
    switch self {
    case .unstart, .waitingRestart(stopped: true):
        return true
    case .executing, .waitingRestart(stopped: false), .done:
        return false
    }
}

var canEnqueue: Bool {
    canStart
}
```

`canStart` / `canEnqueue` may remain internal. Queue code should use these instead of `hasStarted` when deciding whether a task can be accepted or performed.

## 5. Stop Flows

### Public stop and discard stop

Public `task.stop()` and queue `.stopCurrentAndDiscard` remain final-stop flows:

```text
executing -> done(.stop)
```

They still wait for `stopped()` or `stopTimeoutInterval` before queue ownership finishes.

### Requeue stop

Queue `.stopCurrentAndRequeue` uses a separate internal stop-and-wait flow:

```text
executing
 -> waitingRestart(stopped: false)
 -> waitingRestart(stopped: true)
 -> executing
 -> done(...)
```

The first transition happens synchronously when the queue requests the current task to stop for restart. The second transition happens when `stopped()` fires or `stopTimeoutInterval` expires. The third transition happens when the queued task is selected for execution again.

This flow avoids exposing `.done(.stop)` for a task that is not actually finished with the queue lifecycle.

## 6. Queue Semantics

`OnceTimeoutTaskQueue` calls a requeue-specific internal task method for `.stopCurrentAndRequeue`; for example:

```swift
makeRestartStopRequest(timeoutQueue:onStopped:)
```

That method differs from the final stop request by setting `waitingRestart(stopped: false)` immediately instead of `.done(.stop)`.

When restart stop completes:

1. The task transitions to `.waitingRestart(stopped: true)`.
2. The queue reinserts it using original priority and a new sequence.
3. The queue does not emit `taskDidFinish`.
4. The queue selects the next task after any required publish step, preserving the existing pause-from-subscriber behavior.

If the queue later needs to abandon that requeued task, it uses normal cancellation/discard paths from `.waitingRestart(stopped: true)` rather than moving through `.done(.stop)` as part of the restart flow.

The queue continues to emit `taskDidFinish` only when a task truly leaves queue ownership.

## 7. Cancel Semantics

If `cancelAll()` runs while a task is in `.waitingRestart(stopped: false)`, cancellation overrides the restart intent:

```text
waitingRestart(stopped: false) -> done(.cancel)
```

The queue must still wait for `stopped()` or `stopTimeoutInterval` before emitting the finish event for that task. The emitted `TaskFinishEvent.doneType` is `.cancel`.

If `cancelAll()` runs while a task is in `.waitingRestart(stopped: true)` and already back in the waiting queue, it is canceled like any other waiting task and emits `.cancel`.

## 8. Testing Requirements

Tests must cover:

1. `.waitingRestart(stopped: false)` has `hasStarted == true`, `isDone == false`, `canStart == false`, and `canEnqueue == false`.
2. `.waitingRestart(stopped: true)` has `hasStarted == true`, `isDone == false`, `canStart == true`, and `canEnqueue == true`.
3. `.stopCurrentAndRequeue` changes the interrupted task to `.waitingRestart(stopped: false)` immediately after the queue requests stop.
4. The same task changes to `.waitingRestart(stopped: true)` after `stopped()` or stop timeout.
5. The same task later moves to `.executing` when restarted.
6. Requeue still does not emit an intermediate `taskDidFinish` event.
7. `cancelAll()` during `.waitingRestart(stopped: false)` changes state to `.done(.cancel)`, waits for `stopped()` or timeout, then emits `.cancel`.
8. Public `task.stop()` and `.stopCurrentAndDiscard` still end in `.done(.stop)`.

Verification should include:

```bash
rtk xcodebuild test -project Project/RYKit.xcodeproj -scheme RYKitTests -destination 'platform=macOS' -only-testing:RYKitTests/OnceTimeoutTaskTests BUILD_LIBRARY_FOR_DISTRIBUTION=NO
rtk xcodebuild test -project Project/RYKit.xcodeproj -scheme RYKitTests -destination 'platform=macOS' -only-testing:RYKitTests/OnceTimeoutTaskQueueTests BUILD_LIBRARY_FOR_DISTRIBUTION=NO
rtk swift build
```
