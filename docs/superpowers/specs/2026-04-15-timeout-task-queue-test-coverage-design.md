# Timeout Task Queue Test Coverage Design

- Date: 2026-04-15
- Repo: `RYKit`
- Authoring mode: Brainstorming -> Design approved by user

## 1. Goal

Increase unit-test coverage for `OnceTimeoutTask` and `OnceTimeoutTaskQueue` so recent stop/requeue changes are locked down by tests instead of relying on incidental behavior.

The new coverage should verify:

- task state-machine transitions
- stop/restart race handling
- queue ownership and visibility rules
- priority/preemption edge cases

## 2. Scope

In scope:

- Add unit tests to `Project/RYKitTests/TimeoutTaskTests.swift`.
- Add small test-only helpers inside the same test file if they reduce duplication.
- Cover both public behavior and currently relied-on internal semantics that are already reachable from `@testable import RYKit`.
- Verify queue behavior around `waiting`, `current`, and `stopping` ownership states.

Out of scope:

- Changing public `OnceTimeoutTask` or `OnceTimeoutTaskQueue` API.
- Refactoring production code for style only.
- Replacing all existing timing-based tests.
- Adding integration/UI/system tests.

Production code should remain unchanged unless a narrowly scoped test hook is required to observe an existing internal state that cannot otherwise be asserted. The default expectation for this work is no production-code changes.

## 3. Coverage Model

The test additions should be organized around four coverage layers.

### 3.1 Task State Transitions

Verify which states can enter each stop/start path and which calls must be ignored.

This layer focuses on:

- `perform(by:timeoutQueue:)`
- `stop()`
- `stopWhileQueued()`
- `makeStopRequest(timeoutQueue:onStopped:)`
- `makeRestartStopRequest(timeoutQueue:onStopped:)`

### 3.2 Task Race And Idempotency

Verify that repeated or stale signals do not mutate newer task state.

This layer focuses on:

- repeated `stop()` calls
- repeated `stopped()` callbacks
- `stopped()` racing stop timeout
- stale completion or timeout signals after stop/restart flows

### 3.3 Queue Ownership And Visibility

Verify which tasks remain owned by the queue and how that ownership appears through `taskDidFinish` and `allTasks`.

This layer focuses on:

- waiting-task removal
- current-task removal
- stopping-task retention before `stopped()`
- requeue insertion after stop cleanup

### 3.4 Queue Scheduling And Preemption

Verify priority ordering, FIFO behavior, pause/resume boundaries, and stop-based preemption corner cases.

This layer focuses on:

- `.waitCurrentCompletion`
- `.stopCurrentAndDiscard`
- `.stopCurrentAndRequeue`
- higher-priority insertion while already waiting for stop cleanup

## 4. Test Additions

### 4.1 `OnceTimeoutTask` State-Machine Tests

Add tests that cover these missing or weakly covered paths:

1. `perform` is ignored when the task is already `.executing`.
2. `perform` is ignored when the task is already `.done(...)`.
3. `stopWhileQueued()` returns `.stop` only from `.unstart` and `.waitingRestart(stopped: true)`.
4. `stopWhileQueued()` returns `nil` from `.executing`, `.waitingRestart(stopped: false)`, and `.done(...)`.
5. `makeStopRequest(...)` returns `nil` from `.unstart`, `.waitingRestart(stopped: true)`, `.waitingRestart(stopped: false)`, and `.done(...)`.
6. `makeRestartStopRequest(...)` returns `nil` unless the task is `.executing`.
7. `makeRestartStopRequest(...)` moves `.executing` to `.waitingRestart(stopped: false)` immediately.
8. stop-timeout fallback for restart-stop moves `.waitingRestart(stopped: false)` to `.waitingRestart(stopped: true)`.

The goal is to make every reachable task state participate in both:

- at least one valid transition test
- at least one rejected/no-op transition test

### 4.2 `OnceTimeoutTask` Race And Idempotency Tests

Add tests that verify signal uniqueness and stale-signal rejection:

1. Calling `stop()` twice while executing triggers only one stop closure and one final notification.
2. Calling the captured `stopped()` callback twice triggers `onStopped` only once.
3. If stop timeout fires first, a later `stopped()` callback is ignored.
4. If `stopped()` fires first, the later timeout fallback is ignored.
5. After `makeStopRequest(...)`, the old execution-timeout work item cannot later change the task to `.executionTimeout`.
6. After `makeRestartStopRequest(...)`, stale completion and stale execution-timeout signals from the interrupted run cannot move the task to `.done(...)`.

These tests should continue using controlled synchronization points rather than relying on broad sleeps.

### 4.3 `OnceTimeoutTaskQueue` Ownership And Visibility Tests

Add queue tests that verify `allTasks` and finish-event behavior:

1. When paused with waiting tasks only, `allTasks` returns all waiting tasks in effective queue order.
2. When a current task exists and additional waiting tasks are queued, `allTasks` includes both current and waiting tasks exactly once.
3. During stop-based preemption, the interrupted task remains visible through `allTasks` while it is in the queue's `stopping` slot.
4. After a requeue stop finishes, the task reappears in waiting/current ownership without duplication.
5. When a waiting task is stopped directly through `task.stop()`, it disappears from `allTasks` and emits exactly one stop event.
6. When `stopAll(where:)` removes only part of the waiting list, the remaining tasks stay ordered by priority then FIFO.
7. When `stopAll(where:)` matches no tasks, it emits no events and leaves `allTasks` unchanged.

These tests lock down the queue's ownership semantics instead of checking only final execution order.

### 4.4 `OnceTimeoutTaskQueue` Scheduling And Preemption Tests

Add queue tests for missing edge cases in scheduling:

1. Adding a `.done(...)` task to the queue is ignored.
2. Adding a `.waitingRestart(stopped: false)` task to the queue is ignored.
3. Adding a `.waitingRestart(stopped: true)` task is accepted once, but repeated `addTask` on the same instance does not create duplicate queue entries.
4. While a current task is already waiting for stop cleanup, adding an even higher-priority task does not trigger a second preemption flow.
5. While the queue is paused, adding a higher-priority task does not start it and does not preempt the current task.
6. On resume, selection still respects priority/FIFO even when the waiting list contains restart-ready tasks.
7. `.stopCurrentAndRequeue` followed by completion of the higher-priority task restarts the interrupted task before lower-priority tasks.
8. `stopAll(where:)` can override a pending requeue intent to final discard when it explicitly matches the `stopping` task.
9. `stopAll(where:)` does not override the pending requeue intent when it does not match the `stopping` task.

### 4.5 Non-Stoppable Current Task Coverage

The queue implementation contains an effective-strategy fallback:

- if the current task is not stoppable, stop-based strategies behave like `.waitCurrentCompletion`

Add tests that lock down this behavior for both:

- `.stopCurrentAndDiscard`
- `.stopCurrentAndRequeue`

These tests should verify:

- the current task is not stopped
- the higher-priority task waits
- final execution order matches wait-for-completion semantics

If the existing production type cannot express a non-stoppable task without modifying production code, add the smallest possible test-only helper or subclass in tests to exercise the branch.

## 5. Test Support Strategy

The test file already contains repeated patterns around:

- collecting finish events
- polling for state transitions
- capturing `stopped()` callbacks
- asserting done types

To keep the file maintainable, the test changes should introduce small local helpers inside `TimeoutTaskTests.swift`, such as:

- a state-wait helper for asynchronous state transitions
- a reusable event recorder for `taskDidFinish`
- a compact helper for asserting `DoneType`

These helpers should remain local to the test target and should not become general-purpose production utilities.

## 6. Acceptance Criteria

This design is complete when all of the following are true:

1. `OnceTimeoutTask` has explicit tests for valid and invalid transition entry points from every currently reachable state.
2. stop-related tests cover duplicate calls, timeout-vs-callback races, and stale generation protection.
3. `OnceTimeoutTaskQueue` has direct coverage for `allTasks` across waiting/current/stopping ownership states.
4. `stopAll(where:)` is covered for match-all, partial-match, no-match, and stopping-task override cases.
5. all three preemption strategies have dedicated tests, with additional edge coverage around paused queues and already-stopping queues.
6. the non-stoppable-current fallback branch is exercised by tests.
7. new tests reduce duplication rather than increasing unstructured boilerplate.

## 7. Verification

Preferred verification commands:

```bash
rtk xcodebuild test -project Project/RYKit.xcodeproj -scheme RYKitTests -destination 'platform=macOS' -only-testing:RYKitTests/OnceTimeoutTaskTests BUILD_LIBRARY_FOR_DISTRIBUTION=NO
rtk xcodebuild test -project Project/RYKit.xcodeproj -scheme RYKitTests -destination 'platform=macOS' -only-testing:RYKitTests/OnceTimeoutTaskQueueTests BUILD_LIBRARY_FOR_DISTRIBUTION=NO
```

If Xcode test execution remains blocked by the known swiftinterface verification issue in this environment, verification may fall back to:

```bash
rtk swift build
```

and, if available in the local project workflow, any narrower XCTest invocation that still exercises `Project/RYKitTests/TimeoutTaskTests.swift`.
