# OnceTimeoutTask Stop-Only Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Remove cancel semantics from TimeoutTask and use stop for all interruption and queue shutdown behavior.

**Architecture:** `OnceTimeoutTask` exposes one interruption path: `stop()`. `OnceTimeoutTaskQueue` exposes `stopAll(where:)` and routes waiting/current/restart-waiting tasks through stop semantics while preserving finish-event timing.

**Tech Stack:** Swift, Foundation, Combine, XCTest, existing `UnfairLock`.

---

## File Structure

- Modify `Classes/Core/TimeoutTask/OnceTimeoutTask.swift`
  - Remove `DoneType.cancel`, public `cancel()`, `cancelFromQueue()`, and `transitionToCancel(...)`.
  - Make `stop` non-optional again with a default immediate-stop implementation.
  - Add internal stop helpers for queue-owned waiting tasks.
- Modify `Classes/Core/TimeoutTask/OnceTimeoutTaskQueue.swift`
  - Rename `cancelAll(where:)` to `stopAll(where:)`.
  - Stop waiting/current/restart-waiting tasks with `.stop`.
- Modify `Project/RYKitTests/TimeoutTaskTests.swift`
  - Replace cancel tests with stop tests and remove all TimeoutTask `.cancel` expectations.
- Modify `README.md`
  - Replace TimeoutTask examples that use `stop: nil` with default stop or explicit stop.

## Verification Commands

```bash
rtk xcodebuild test -project Project/RYKit.xcodeproj -scheme RYKitTests -destination 'platform=macOS' -only-testing:RYKitTests/OnceTimeoutTaskTests BUILD_LIBRARY_FOR_DISTRIBUTION=NO
rtk xcodebuild test -project Project/RYKit.xcodeproj -scheme RYKitTests -destination 'platform=macOS' -only-testing:RYKitTests/OnceTimeoutTaskQueueTests BUILD_LIBRARY_FOR_DISTRIBUTION=NO
rtk xcodebuild test -project Project/RYKit.xcodeproj -scheme RYKitTests -destination 'platform=macOS' BUILD_LIBRARY_FOR_DISTRIBUTION=NO
rtk swift build
rtk proxy git diff --check
```

Expected final result: all commands pass. Normal Xcode tests without `BUILD_LIBRARY_FOR_DISTRIBUTION=NO` are known to fail on project-wide Swift interface verification and should be reported separately if rerun.

---

### Task 1: Remove Task Cancel API

**Files:**
- Modify: `Project/RYKitTests/TimeoutTaskTests.swift`
- Modify: `Classes/Core/TimeoutTask/OnceTimeoutTask.swift`

- [ ] **Step 1: Replace task cancel tests with stop-default tests**

In `Project/RYKitTests/TimeoutTaskTests.swift`, remove `test_cancel_whenExecutingUpdatesState` entirely.

Add these tests inside `OnceTimeoutTaskTests` near the existing stop tests:

```swift
func test_defaultStop_immediatelyStopsExecutingTask() {
    let started = expectation(description: "started")
    let stopped = expectation(description: "stopped")
    let task = OnceTimeoutTask<Int, TestError>(
        flag: "default-stop",
        executionTimeoutInterval: .seconds(10),
        stopTimeoutInterval: .milliseconds(100),
        execute: { _ in started.fulfill() }
    )
    task.onDone = { doneType in
        if case .stop = doneType {
            stopped.fulfill()
        }
    }

    task.perform(by: .global(), timeoutQueue: .global())
    wait(for: [started], timeout: 1.0)
    task.stop()

    wait(for: [stopped], timeout: 1.0)
    guard case .done(.stop) = task.state else {
        XCTFail("Expected done(stop), got \(task.state)")
        return
    }
}

func test_asyncInit_defaultStop_immediatelyStopsExecutingTask() async throws {
    let task = OnceTimeoutTask<Int, TestError>(
        flag: "async-default-stop",
        executionTimeoutInterval: .seconds(10),
        stopTimeoutInterval: .milliseconds(100),
        execute: {
            try? await Task.sleep(nanoseconds: 500_000_000)
            return .success(1)
        }
    )

    task.perform(by: .global(), timeoutQueue: .global())
    try await Task.sleep(nanoseconds: 100_000_000)
    task.stop()
    try await Task.sleep(nanoseconds: 100_000_000)

    guard case .done(.stop) = task.state else {
        XCTFail("Expected done(stop), got \(task.state)")
        return
    }
}
```

Update `test_stopNil_publicStopDoesNothing` and `test_asyncInit_acceptsNilStop` from the optional-stop work:

- Rename `test_stopNil_publicStopDoesNothing` to `test_defaultStop_publicStopStops`.
- Replace `stop: nil` with no `stop:` argument.
- Change its assertions to expect `.done(.stop)`.
- Rename `test_asyncInit_acceptsNilStop` to `test_asyncInit_usesDefaultStop`.
- Remove `stop: nil` from the initializer.

- [ ] **Step 2: Run task tests and verify they fail**

```bash
rtk xcodebuild test -project Project/RYKit.xcodeproj -scheme RYKitTests -destination 'platform=macOS' -only-testing:RYKitTests/OnceTimeoutTaskTests BUILD_LIBRARY_FOR_DISTRIBUTION=NO
```

Expected: FAIL because `stop` still requires an argument and cancel API still exists.

- [ ] **Step 3: Remove cancel from task API**

In `Classes/Core/TimeoutTask/OnceTimeoutTask.swift`:

Remove from `DoneType`:

```swift
case cancel
```

Remove:

```swift
public func cancel()
func cancelFromQueue() -> DoneType?
private func transitionToCancel(allowUnstarted: Bool, notify: Bool) -> DoneType?
```

Remove cancel-related doc comments.

- [ ] **Step 4: Make stop non-optional with default**

Change stored stop action:

```swift
private let stopAction: Stop
```

Update `isStoppable` to remain true:

```swift
var isStoppable: Bool {
    true
}
```

Change callback initializer signature:

```swift
public init(
    flag: String,
    executionTimeoutInterval: DispatchTimeInterval?,
    stopTimeoutInterval: DispatchTimeInterval?,
    execute: @escaping (@escaping Completed) -> Void,
    stop: @escaping Stop = { stopped in stopped() }
)
```

Change async initializer signature:

```swift
public convenience init(
    flag: String,
    executionTimeoutInterval: DispatchTimeInterval?,
    stopTimeoutInterval: DispatchTimeInterval?,
    execute: @escaping () async -> Result<T, E>,
    stop: @escaping () async -> Void = {}
)
```

Bridge async stop without optional mapping:

```swift
let bridgedStop: Stop = { stopped in
    Task {
        await stop()
        stopped()
    }
}
```

- [ ] **Step 5: Update stop request helper for non-optional stop**

In the private stop request helper, remove:

```swift
guard let stopAction else {
    lock.unlock()
    return nil
}
```

Keep invoking `stopAction(stopped)` outside the lock.

- [ ] **Step 6: Add queue-owned direct stop helper**

Add this internal helper near `makeStopRequest`:

```swift
@discardableResult
func stopFromQueue() -> DoneType? {
    lock.lock()
    switch currentState {
    case .unstart, .waitingRestart(stopped: true):
        currentState = .done(.stop)
        runGeneration &+= 1
        stopGeneration &+= 1
        executionTimeoutItem?.cancel()
        executionTimeoutItem = nil
        stopTimeoutItem?.cancel()
        stopTimeoutItem = nil
        stopFinished = nil
        lock.unlock()
        return .stop
    default:
        lock.unlock()
        return nil
    }
}
```

This replaces queue cancellation for waiting tasks. Executing tasks still use normal stop request paths.

- [ ] **Step 7: Run task tests**

```bash
rtk xcodebuild test -project Project/RYKit.xcodeproj -scheme RYKitTests -destination 'platform=macOS' -only-testing:RYKitTests/OnceTimeoutTaskTests BUILD_LIBRARY_FOR_DISTRIBUTION=NO
```

Expected: PASS.

- [ ] **Step 8: Commit Task 1**

```bash
rtk git add Classes/Core/TimeoutTask/OnceTimeoutTask.swift Project/RYKitTests/TimeoutTaskTests.swift
rtk git commit -m "Remove timeout task cancel API" -m "Timeout tasks now use stop as the only interruption path, with default stop implementations for callback and async initializers." -m "Constraint: DoneType.cancel and public cancel are intentionally removed" -m "Confidence: high" -m "Scope-risk: moderate" -m "Tested: xcodebuild OnceTimeoutTaskTests with BUILD_LIBRARY_FOR_DISTRIBUTION=NO"
```

---

### Task 2: Rename Queue Cancel-All To Stop-All

**Files:**
- Modify: `Project/RYKitTests/TimeoutTaskTests.swift`
- Modify: `Classes/Core/TimeoutTask/OnceTimeoutTaskQueue.swift`

- [ ] **Step 1: Update queue tests from cancelAll to stopAll**

In `Project/RYKitTests/TimeoutTaskTests.swift`, rename and update these tests:

- `test_cancelAll_cancelsWaitingAndCurrentAndEmitsEvents` -> `test_stopAll_stopsWaitingAndCurrentAndEmitsEvents`
- `test_cancelAllDuringPublicStopWaitKeepsCurrentUntilStoppedAndCancelsWaiting` -> `test_stopAllDuringPublicStopWaitKeepsCurrentUntilStoppedAndStopsWaiting`
- `test_cancelAllDuringWaitingRestartFalseFinishesAsCancelAfterStopped` -> `test_stopAllDuringWaitingRestartFalseFinishesAsStopAfterStopped`
- `test_cancelAll_duringStopWaitAbandonsPendingPreemptionAndEmitsStoppedTaskOnStopCompletion` -> `test_stopAll_duringStopWaitAbandonsPendingPreemptionAndEmitsStoppedTaskOnStopCompletion`

Replace each `queue.cancelAll(...)` call with `queue.stopAll(...)`.

Replace `.cancel` expectations with `.stop`.

Rename local variables like `waitingCancelled` to `waitingStopped` where they are in TimeoutTask-specific tests.

- [ ] **Step 2: Run queue tests and verify they fail**

```bash
rtk xcodebuild test -project Project/RYKit.xcodeproj -scheme RYKitTests -destination 'platform=macOS' -only-testing:RYKitTests/OnceTimeoutTaskQueueTests BUILD_LIBRARY_FOR_DISTRIBUTION=NO
```

Expected: FAIL because `stopAll(where:)` does not exist yet and queue still has cancel helpers.

- [ ] **Step 3: Rename queue API and use stop helpers**

In `Classes/Core/TimeoutTask/OnceTimeoutTaskQueue.swift`, replace `cancelAll(where:)` with:

```swift
/// Stops all waiting tasks and the current task when they match the filter.
///
/// If a task is already waiting for stop cleanup, the queue keeps ownership until `stopped()`
/// or stop timeout, then emits the final event.
public func stopAll(where block: ((OnceTimeoutTask<T, E>) -> Bool)? = nil) {
    var events: [TaskFinishEvent] = []

    lock.lock()
    let itemsToStop: [QueuedTask]
    if let block {
        itemsToStop = waiting.filter { queued in
            block(queued.task)
        }
        waiting.removeAll { queued in
            block(queued.task)
        }
    } else {
        itemsToStop = waiting
        waiting.removeAll()
    }

    if let stopping, block?(stopping.task) ?? true {
        _ = stopping.task.stopFromQueue()
        stopDisposition = .discard
    }

    for item in itemsToStop {
        if let doneType = item.task.stopFromQueue() {
            events.append(TaskFinishEvent(flag: item.task.flag, task: item.task, doneType: doneType))
        }
    }

    let currentStopRequest: (() -> Void)?
    if let current, block?(current.task) ?? true {
        currentStopRequest = prepareStopLocked(disposition: .discard)
    } else {
        currentStopRequest = nil
    }
    let taskToStart = takeNextIfPossible()
    lock.unlock()

    publish(events)
    currentStopRequest?()
    start(taskToStart)
}
```

This preserves stop cleanup waiting for the current task, instead of force-finishing it.
It also starts the next waiting task when only waiting tasks were stopped and no current/stopping task blocks the queue.

- [ ] **Step 4: Run queue tests**

```bash
rtk xcodebuild test -project Project/RYKit.xcodeproj -scheme RYKitTests -destination 'platform=macOS' -only-testing:RYKitTests/OnceTimeoutTaskQueueTests BUILD_LIBRARY_FOR_DISTRIBUTION=NO
```

Expected: PASS.

- [ ] **Step 5: Commit Task 2**

```bash
rtk git add Classes/Core/TimeoutTask/OnceTimeoutTaskQueue.swift Project/RYKitTests/TimeoutTaskTests.swift
rtk git commit -m "Rename queue shutdown to stopAll" -m "Queue-wide interruption now uses stop semantics and stop events instead of cancel naming or cancel done types." -m "Constraint: No cancelAll alias remains" -m "Confidence: high" -m "Scope-risk: moderate" -m "Tested: xcodebuild OnceTimeoutTaskQueueTests with BUILD_LIBRARY_FOR_DISTRIBUTION=NO"
```

---

### Task 3: Remove Remaining TimeoutTask Cancel References

**Files:**
- Modify: `README.md`
- Modify: `Classes/Core/TimeoutTask/OnceTimeoutTask.swift`
- Modify: `Classes/Core/TimeoutTask/OnceTimeoutTaskQueue.swift`
- Modify: `Project/RYKitTests/TimeoutTaskTests.swift`

- [ ] **Step 1: Update README TimeoutTask examples**

In the persistent task examples, replace `stop: nil` with omitted stop argument:

```swift
let persistentTask = OnceTimeoutTask<String, Error>(
    flag: "persistent",
    executionTimeoutInterval: nil,
    stopTimeoutInterval: nil,
    execute: { _ in
        // Complete later, or keep running.
    }
)
```

- [ ] **Step 2: Scan TimeoutTask source/tests/docs for cancel**

Run:

```bash
rtk rg -n "cancel|Cancel|cancelAll|\\.cancel|cancelFromQueue|transitionToCancel" Classes/Core/TimeoutTask Project/RYKitTests/TimeoutTaskTests.swift README.md
```

Expected:

- No matches in `Classes/Core/TimeoutTask`.
- No matches in `Project/RYKitTests/TimeoutTaskTests.swift` except `cancellables` from Combine storage if present.
- README matches outside TimeoutTask examples are acceptable, such as HTTP request strategy and Combine `cancellables`.

- [ ] **Step 3: Run focused task tests**

```bash
rtk xcodebuild test -project Project/RYKit.xcodeproj -scheme RYKitTests -destination 'platform=macOS' -only-testing:RYKitTests/OnceTimeoutTaskTests BUILD_LIBRARY_FOR_DISTRIBUTION=NO
```

Expected: PASS.

- [ ] **Step 4: Run focused queue tests**

```bash
rtk xcodebuild test -project Project/RYKit.xcodeproj -scheme RYKitTests -destination 'platform=macOS' -only-testing:RYKitTests/OnceTimeoutTaskQueueTests BUILD_LIBRARY_FOR_DISTRIBUTION=NO
```

Expected: PASS.

- [ ] **Step 5: Run full fallback Xcode tests**

```bash
rtk xcodebuild test -project Project/RYKit.xcodeproj -scheme RYKitTests -destination 'platform=macOS' BUILD_LIBRARY_FOR_DISTRIBUTION=NO
```

Expected: PASS.

- [ ] **Step 6: Run SwiftPM build and diff hygiene**

```bash
rtk swift build
rtk proxy git diff --check
```

Expected: PASS.

- [ ] **Step 7: Commit Task 3**

```bash
rtk git add README.md Classes/Core/TimeoutTask/OnceTimeoutTask.swift Classes/Core/TimeoutTask/OnceTimeoutTaskQueue.swift Project/RYKitTests/TimeoutTaskTests.swift
rtk git commit -m "Remove timeout task cancel references" -m "TimeoutTask source, tests, and examples now use stop-only terminology after removing cancel APIs." -m "Confidence: high" -m "Scope-risk: narrow" -m "Tested: focused task and queue tests, full fallback Xcode test suite, swift build, diff check"
```
