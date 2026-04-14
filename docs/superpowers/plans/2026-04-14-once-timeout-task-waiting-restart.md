# OnceTimeoutTask Waiting Restart Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add `OnceTimeoutTask.State.waitingRestart(stopped:)` so requeued tasks are visibly distinct from never-started tasks.

**Architecture:** `OnceTimeoutTask` owns the new state and exposes internal queue-only restart-stop helpers. `OnceTimeoutTaskQueue` uses those helpers only for `.stopCurrentAndRequeue`, keeps final-stop behavior unchanged for public `stop()` and `.stopCurrentAndDiscard`, and preserves existing finish-event ownership semantics.

**Tech Stack:** Swift, Foundation, Combine, XCTest, existing `UnfairLock`.

---

## File Structure

- Modify `Classes/Core/TimeoutTask/OnceTimeoutTask.swift`
  - Add `State.waitingRestart(stopped:)`, `canStart`, `canEnqueue`, restart-stop request handling, restart-ready transition, and cancel support for waiting restart states.
- Modify `Classes/Core/TimeoutTask/OnceTimeoutTaskQueue.swift`
  - Use `canEnqueue`, use restart-specific stop requests for `.stopCurrentAndRequeue`, reinsert only after `waitingRestart(stopped: true)`, and emit `.cancel` when `cancelAll()` abandons restart waiting.
- Modify `Project/RYKitTests/TimeoutTaskTests.swift`
  - Add state-machine tests and update queue preemption/cancel tests to assert `waitingRestart(stopped:)` transitions.

## Verification Commands

Use these commands after implementation:

```bash
rtk xcodebuild test -project Project/RYKit.xcodeproj -scheme RYKitTests -destination 'platform=macOS' -only-testing:RYKitTests/OnceTimeoutTaskTests BUILD_LIBRARY_FOR_DISTRIBUTION=NO
rtk xcodebuild test -project Project/RYKit.xcodeproj -scheme RYKitTests -destination 'platform=macOS' -only-testing:RYKitTests/OnceTimeoutTaskQueueTests BUILD_LIBRARY_FOR_DISTRIBUTION=NO
rtk xcodebuild test -project Project/RYKit.xcodeproj -scheme RYKitTests -destination 'platform=macOS' BUILD_LIBRARY_FOR_DISTRIBUTION=NO
rtk swift build
rtk proxy git diff --check
```

Expected final result: all commands pass. Normal Xcode tests without `BUILD_LIBRARY_FOR_DISTRIBUTION=NO` are currently known to fail on project-wide Swift interface verification; report that separately if rerun.

---

### Task 1: Add Waiting Restart State To OnceTimeoutTask

**Files:**
- Modify: `Project/RYKitTests/TimeoutTaskTests.swift`
- Modify: `Classes/Core/TimeoutTask/OnceTimeoutTask.swift`

- [ ] **Step 1: Add state semantic tests**

In `Project/RYKitTests/TimeoutTaskTests.swift`, inside `OnceTimeoutTaskTests`, add these tests after `test_init_storesFlagAndStateIsUnstart`:

```swift
func test_waitingRestartFalse_stateSemantics() {
    let task = OnceTimeoutTask<Int, TestError>(
        flag: "restart",
        executionTimeoutInterval: .seconds(10),
        stopTimeoutInterval: .milliseconds(100),
        execute: { _ in },
        stop: { stopped in stopped() }
    )

    task.setWaitingRestartForTest(stopped: false)

    XCTAssertTrue(task.state.hasStarted)
    XCTAssertFalse(task.state.isDone)
    XCTAssertFalse(task.state.canStart)
    XCTAssertFalse(task.state.canEnqueue)
}

func test_waitingRestartTrue_stateSemantics() {
    let task = OnceTimeoutTask<Int, TestError>(
        flag: "restart",
        executionTimeoutInterval: .seconds(10),
        stopTimeoutInterval: .milliseconds(100),
        execute: { _ in },
        stop: { stopped in stopped() }
    )

    task.setWaitingRestartForTest(stopped: true)

    XCTAssertTrue(task.state.hasStarted)
    XCTAssertFalse(task.state.isDone)
    XCTAssertTrue(task.state.canStart)
    XCTAssertTrue(task.state.canEnqueue)
}

func test_perform_canStartFromWaitingRestartStoppedTrue() {
    let started = expectation(description: "started")
    let task = OnceTimeoutTask<Int, TestError>(
        flag: "restart",
        executionTimeoutInterval: .seconds(10),
        stopTimeoutInterval: .milliseconds(100),
        execute: { _ in started.fulfill() },
        stop: { stopped in stopped() }
    )

    task.setWaitingRestartForTest(stopped: true)
    task.perform(by: .global(), timeoutQueue: .global())

    wait(for: [started], timeout: 1.0)
    if case .executing = task.state {
    } else {
        XCTFail("Expected executing, got \(task.state)")
    }
}

func test_perform_doesNotStartFromWaitingRestartStoppedFalse() {
    let started = expectation(description: "started")
    started.isInverted = true
    let task = OnceTimeoutTask<Int, TestError>(
        flag: "restart",
        executionTimeoutInterval: .seconds(10),
        stopTimeoutInterval: .milliseconds(100),
        execute: { _ in started.fulfill() },
        stop: { stopped in stopped() }
    )

    task.setWaitingRestartForTest(stopped: false)
    task.perform(by: .global(), timeoutQueue: .global())

    wait(for: [started], timeout: 0.2)
    guard case .waitingRestart(stopped: false) = task.state else {
        XCTFail("Expected waitingRestart(false), got \(task.state)")
        return
    }
}
```

Also add this internal test hook near the bottom of `Project/RYKitTests/TimeoutTaskTests.swift`, outside the test classes:

```swift
private extension OnceTimeoutTask {
    func setWaitingRestartForTest(stopped: Bool) {
        setWaitingRestart(stopped: stopped)
    }
}
```

- [ ] **Step 2: Run task tests and verify they fail**

Run:

```bash
rtk xcodebuild test -project Project/RYKit.xcodeproj -scheme RYKitTests -destination 'platform=macOS' -only-testing:RYKitTests/OnceTimeoutTaskTests BUILD_LIBRARY_FOR_DISTRIBUTION=NO
```

Expected: FAIL with missing `waitingRestart`, `canStart`, `canEnqueue`, or `setWaitingRestart` errors.

- [ ] **Step 3: Add state cases and computed properties**

In `Classes/Core/TimeoutTask/OnceTimeoutTask.swift`, replace `State` with:

```swift
public enum State {
    case unstart, executing, waitingRestart(stopped: Bool), done(DoneType)
    
    var isDone: Bool {
        if case .done = self { true } else { false }
    }
    
    var hasStarted: Bool {
        if case .unstart = self { false } else { true }
    }

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
}
```

- [ ] **Step 4: Allow perform from restart-ready state**

In `perform(by:timeoutQueue:)`, replace:

```swift
guard case .unstart = currentState else {
    lock.unlock()
    return
}
```

with:

```swift
guard currentState.canStart else {
    lock.unlock()
    return
}
```

- [ ] **Step 5: Add internal restart state helpers**

In `Classes/Core/TimeoutTask/OnceTimeoutTask.swift`, add these internal helpers near `resetForRequeue()`:

```swift
func setWaitingRestart(stopped: Bool) {
    lock.lock()
    currentState = .waitingRestart(stopped: stopped)
    lock.unlock()
}

@discardableResult
func markWaitingRestartStopped() -> Bool {
    lock.lock()
    defer { lock.unlock() }
    guard case .waitingRestart(stopped: false) = currentState else {
        return false
    }
    currentState = .waitingRestart(stopped: true)
    return true
}
```

Update `transitionToCancel(allowUnstarted:notify:)` so cancellation can claim waiting restart states:

```swift
switch currentState {
case .executing:
    break
case .unstart where allowUnstarted:
    break
case .waitingRestart where allowUnstarted:
    break
default:
    lock.unlock()
    return nil
}
```

Keep `resetForRequeue()` for now; Task 2 will remove queue usage of it.

- [ ] **Step 6: Run task tests**

Run:

```bash
rtk xcodebuild test -project Project/RYKit.xcodeproj -scheme RYKitTests -destination 'platform=macOS' -only-testing:RYKitTests/OnceTimeoutTaskTests BUILD_LIBRARY_FOR_DISTRIBUTION=NO
```

Expected: PASS.

- [ ] **Step 7: Commit Task 1**

```bash
rtk git add Classes/Core/TimeoutTask/OnceTimeoutTask.swift Project/RYKitTests/TimeoutTaskTests.swift
rtk git commit -m "Add waiting restart task state" -m "Requeued timeout tasks need an observable state between stopped execution and the next run, distinct from never-started tasks." -m "Constraint: waitingRestart(stopped: false) is not startable; waitingRestart(stopped: true) is startable" -m "Confidence: high" -m "Scope-risk: narrow" -m "Tested: xcodebuild OnceTimeoutTaskTests with BUILD_LIBRARY_FOR_DISTRIBUTION=NO"
```

---

### Task 2: Use Waiting Restart In Queue Requeue Flow

**Files:**
- Modify: `Project/RYKitTests/TimeoutTaskTests.swift`
- Modify: `Classes/Core/TimeoutTask/OnceTimeoutTask.swift`
- Modify: `Classes/Core/TimeoutTask/OnceTimeoutTaskQueue.swift`

- [ ] **Step 1: Add queue transition tests**

In `Project/RYKitTests/TimeoutTaskTests.swift`, update `test_stopCurrentAndRequeue_doesNotEmitIntermediateStopAndRunsStoppedTaskAgain`.

First, replace the existing `let high = makeTask(...)` in that test with a high-priority task that does not finish until the test has observed `waitingRestart(stopped: true)`:

```swift
let allowHighToFinish = DispatchSemaphore(value: 0)
let high = OnceTimeoutTask<Int, TestError>(
    flag: "high",
    executionTimeoutInterval: .seconds(10),
    stopTimeoutInterval: .milliseconds(100),
    execute: { completed in
        lock.lock()
        executionOrder.append("high")
        lock.unlock()
        allowHighToFinish.wait()
        completed(.success(2))
    },
    stop: { stopped in
        stopped()
    }
)
```

Then add these assertions after the high-priority task is added and before `stoppedCallback?()`:

```swift
guard case .waitingRestart(stopped: false) = current.state else {
    XCTFail("Expected waitingRestart(false), got \(current.state)")
    return
}
```

Then after `stoppedCallback?()` and before `wait(for: [highFinished, currentFinished], timeout: 3.0)`, add a bounded wait that observes `waitingRestart(stopped: true)` while the high-priority task is intentionally blocked:

```swift
let restartReady = expectation(description: "restart ready")
DispatchQueue.global().async {
    let deadline = Date().addingTimeInterval(1.0)
    while Date() < deadline {
        if case .waitingRestart(stopped: true) = current.state {
            restartReady.fulfill()
            return
        }
        Thread.sleep(forTimeInterval: 0.01)
    }
}
wait(for: [restartReady], timeout: 1.0)
allowHighToFinish.signal()
```

Append this new test to `OnceTimeoutTaskQueueTests`:

```swift
func test_cancelAllDuringWaitingRestartFalseFinishesAsCancelAfterStopped() {
    let queue = OnceTimeoutTaskQueue<Int, TestError>(executeQueue: .global())
    let currentStarted = expectation(description: "current started")
    let currentFinished = expectation(description: "current finished")
    var stoppedCallback: (() -> Void)?
    var eventDoneType: OnceTimeoutTask<Int, TestError>.DoneType?

    queue.taskDidFinish
        .sink { event in
            if event.flag == "current" {
                eventDoneType = event.doneType
                currentFinished.fulfill()
            }
        }
        .store(in: &cancellables)

    let current = OnceTimeoutTask<Int, TestError>(
        flag: "current",
        executionTimeoutInterval: .seconds(10),
        stopTimeoutInterval: .seconds(1),
        execute: { _ in currentStarted.fulfill() },
        stop: { stopped in stoppedCallback = stopped }
    )
    let high = makeTask(flag: "high", value: 2)

    queue.addTask(current, priority: 0)
    wait(for: [currentStarted], timeout: 1.0)
    queue.addTask(high, priority: 10, preemptionStrategy: .stopCurrentAndRequeue)

    guard case .waitingRestart(stopped: false) = current.state else {
        XCTFail("Expected waitingRestart(false), got \(current.state)")
        return
    }

    queue.cancelAll()

    guard case .done(.cancel) = current.state else {
        XCTFail("Expected done(cancel), got \(current.state)")
        return
    }

    stoppedCallback?()
    wait(for: [currentFinished], timeout: 1.0)

    guard case .cancel = eventDoneType else {
        XCTFail("Expected cancel finish event")
        return
    }
}
```

- [ ] **Step 2: Run queue tests and verify they fail**

Run:

```bash
rtk xcodebuild test -project Project/RYKit.xcodeproj -scheme RYKitTests -destination 'platform=macOS' -only-testing:RYKitTests/OnceTimeoutTaskQueueTests BUILD_LIBRARY_FOR_DISTRIBUTION=NO
```

Expected: FAIL because `.stopCurrentAndRequeue` still uses final-stop `.done(.stop)` and `resetForRequeue()`.

- [ ] **Step 3: Add restart stop request to OnceTimeoutTask**

In `Classes/Core/TimeoutTask/OnceTimeoutTask.swift`, add:

```swift
func makeRestartStopRequest(timeoutQueue: DispatchQueue, onStopped: @escaping () -> Void) -> (() -> Void)? {
    makeStopRequest(
        timeoutQueue: timeoutQueue,
        stoppedState: .waitingRestart(stopped: true),
        onStopped: onStopped
    )
}
```

Refactor the current `makeStopRequest(timeoutQueue:onStopped:)` so it delegates to a private helper:

```swift
func makeStopRequest(timeoutQueue: DispatchQueue, onStopped: @escaping () -> Void) -> (() -> Void)? {
    makeStopRequest(
        timeoutQueue: timeoutQueue,
        stoppedState: .done(.stop),
        onStopped: onStopped
    )
}

private func makeStopRequest(
    timeoutQueue: DispatchQueue,
    stoppedState: State,
    onStopped: @escaping () -> Void
) -> (() -> Void)? {
    lock.lock()
    guard case .executing = currentState else {
        lock.unlock()
        return nil
    }
    stopGeneration &+= 1
    let generation = stopGeneration
    let stopTimeoutItem = DispatchWorkItem { [weak self] in
        self?.finishStop(stopGeneration: generation, stoppedState: stoppedState)
    }
    let stopped: Stopped = { [weak self] in
        self?.finishStop(stopGeneration: generation, stoppedState: stoppedState)
    }
    currentState = {
        switch stoppedState {
        case .waitingRestart:
            return .waitingRestart(stopped: false)
        default:
            return .done(.stop)
        }
    }()
    executionTimeoutItem?.cancel()
    executionTimeoutItem = nil
    self.stopTimeoutItem = stopTimeoutItem
    stopFinished = onStopped
    let interval = stopTimeoutInterval
    let stopAction = self.stopAction
    lock.unlock()
    
    if case .never = interval {
    } else {
        timeoutQueue.asyncAfter(deadline: .now() + interval, execute: stopTimeoutItem)
    }
    
    return {
        stopAction(stopped)
    }
}
```

Replace `finishStop(stopGeneration:)` with:

```swift
private func finishStop(stopGeneration expectedStopGeneration: UInt64, stoppedState: State) {
    let handler: (() -> Void)?
    
    lock.lock()
    guard let stopFinished, expectedStopGeneration == stopGeneration else {
        lock.unlock()
        return
    }
    if case .waitingRestart(stopped: false) = currentState {
        currentState = stoppedState
    }
    handler = stopFinished
    self.stopFinished = nil
    stopTimeoutItem?.cancel()
    stopTimeoutItem = nil
    lock.unlock()
    
    handler?()
}
```

This preserves public final-stop behavior because final stop enters `.done(.stop)` immediately and `finishStop` only changes `.waitingRestart(stopped: false)` states.

- [ ] **Step 4: Update queue requeue path**

In `Classes/Core/TimeoutTask/OnceTimeoutTaskQueue.swift`, update `prepareStopLocked` so `.requeue` uses `makeRestartStopRequest`:

```swift
let request: (() -> Void)?
switch disposition {
case .discard:
    request = current.task.makeStopRequest(timeoutQueue: timeoutQueue, onStopped: { [weak self, weak task = current.task] in
        guard let task else { return }
        self?.handleTaskStopped(task)
    })
case .requeue:
    request = current.task.makeRestartStopRequest(timeoutQueue: timeoutQueue, onStopped: { [weak self, weak task = current.task] in
        guard let task else { return }
        self?.handleTaskStopped(task)
    })
}
guard let request else {
    return nil
}
```

In `handleTaskStopped`, replace the `.requeue` case with:

```swift
case .requeue:
    if stopping.task.state.canEnqueue {
        insert(makeQueuedTaskLocked(task: stopping.task, priority: stopping.priority))
    }
    event = nil
```

Do not call `resetForRequeue()` in the queue anymore.

In `addTask`, replace:

```swift
guard !task.state.hasStarted else {
    return
}
```

with:

```swift
guard task.state.canEnqueue else {
    return
}
```

- [ ] **Step 5: Preserve cancel semantics for restart waiting**

Update `cancelAll()` so it also claims a task currently held in `stopping`:

```swift
if let stopping {
    _ = stopping.task.cancelFromQueue()
    stopDisposition = .discard
}
```

This code must run while the queue lock is held, before unlocking and publishing immediate waiting/current events. It must not publish an event for `stopping` immediately; `handleTaskStopped` emits that event after `stopped()` or stop timeout. With Task 1's `transitionToCancel` update, this changes `.waitingRestart(stopped: false)` to `.done(.cancel)` immediately, while still preserving the wait-before-finish-event rule.

Update `handleTaskStopped` so when `stopDisposition == .discard` it emits the actual current done type from task state:

```swift
case .discard, .none:
    let doneType: OnceTimeoutTask<T, E>.DoneType
    if case .done(let currentDoneType) = task.state {
        doneType = currentDoneType
    } else {
        doneType = .stop
    }
    event = TaskFinishEvent(flag: task.flag, task: task, doneType: doneType)
```

This is what makes `cancelAll()` during `.waitingRestart(stopped: false)` emit `.cancel` after stop completion.

- [ ] **Step 6: Run queue tests**

Run:

```bash
rtk xcodebuild test -project Project/RYKit.xcodeproj -scheme RYKitTests -destination 'platform=macOS' -only-testing:RYKitTests/OnceTimeoutTaskQueueTests BUILD_LIBRARY_FOR_DISTRIBUTION=NO
```

Expected: PASS.

- [ ] **Step 7: Run task tests**

Run:

```bash
rtk xcodebuild test -project Project/RYKit.xcodeproj -scheme RYKitTests -destination 'platform=macOS' -only-testing:RYKitTests/OnceTimeoutTaskTests BUILD_LIBRARY_FOR_DISTRIBUTION=NO
```

Expected: PASS.

- [ ] **Step 8: Commit Task 2**

```bash
rtk git add Classes/Core/TimeoutTask/OnceTimeoutTask.swift Classes/Core/TimeoutTask/OnceTimeoutTaskQueue.swift Project/RYKitTests/TimeoutTaskTests.swift
rtk git commit -m "Use waiting restart for requeued tasks" -m "Queue restart preemption now exposes waitingRestart(stopped:) while preserving final stop and finish-event semantics." -m "Constraint: cancelAll during waitingRestart(false) finishes as cancel but waits for stopped or timeout before publishing" -m "Confidence: high" -m "Scope-risk: moderate" -m "Tested: xcodebuild OnceTimeoutTaskTests and OnceTimeoutTaskQueueTests with BUILD_LIBRARY_FOR_DISTRIBUTION=NO"
```

---

### Task 3: Final Verification

**Files:**
- Verify: `Classes/Core/TimeoutTask/OnceTimeoutTask.swift`
- Verify: `Classes/Core/TimeoutTask/OnceTimeoutTaskQueue.swift`
- Verify: `Project/RYKitTests/TimeoutTaskTests.swift`

- [ ] **Step 1: Run focused task tests**

```bash
rtk xcodebuild test -project Project/RYKit.xcodeproj -scheme RYKitTests -destination 'platform=macOS' -only-testing:RYKitTests/OnceTimeoutTaskTests BUILD_LIBRARY_FOR_DISTRIBUTION=NO
```

Expected: PASS.

- [ ] **Step 2: Run focused queue tests**

```bash
rtk xcodebuild test -project Project/RYKit.xcodeproj -scheme RYKitTests -destination 'platform=macOS' -only-testing:RYKitTests/OnceTimeoutTaskQueueTests BUILD_LIBRARY_FOR_DISTRIBUTION=NO
```

Expected: PASS.

- [ ] **Step 3: Run full fallback Xcode test suite**

```bash
rtk xcodebuild test -project Project/RYKit.xcodeproj -scheme RYKitTests -destination 'platform=macOS' BUILD_LIBRARY_FOR_DISTRIBUTION=NO
```

Expected: PASS.

- [ ] **Step 4: Run SwiftPM build**

```bash
rtk swift build
```

Expected: PASS.

- [ ] **Step 5: Run diff hygiene**

```bash
rtk proxy git diff --check
rtk git status --short
```

Expected: no diff-check errors; status should show only intentional uncommitted changes if any.
