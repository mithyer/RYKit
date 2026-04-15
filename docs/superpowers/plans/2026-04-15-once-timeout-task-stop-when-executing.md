# OnceTimeoutTask StopWhenExecuting Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Rename the cooperative stop callback to `StopWhenExecuting` / `stopWhenExecuting` and make direct `task.stop()` use the same immediate-stop semantics as `stopAll(where:)` for non-executing queued states.

**Architecture:** `OnceTimeoutTask` keeps one public interruption entrypoint, `stop()`. Internally, executing tasks still go through cooperative stop callbacks, while `.unstart` and `.waitingRestart(stopped: true)` take a direct terminal `.done(.stop)` path without invoking `stopWhenExecuting`. The queue API surface stays stop-only and only needs naming alignment in docs/comments.

**Tech Stack:** Swift, Foundation, Combine, XCTest, existing `UnfairLock`.

---

## File Structure

- Modify `Classes/Core/TimeoutTask/OnceTimeoutTask.swift`
  - Rename `Stop` to `StopWhenExecuting`, rename initializer parameter to `stopWhenExecuting`, and unify direct `stop()` semantics for non-executing startable states.
- Modify `Project/RYKitTests/TimeoutTaskTests.swift`
  - Update initializer call sites to `stopWhenExecuting:` and add direct-stop tests for `.unstart` and `.waitingRestart(stopped: true)`.
- Modify `README.md`
  - Rename TimeoutTask examples from `stop:` to `stopWhenExecuting:`.
- Optionally modify `Classes/Core/TimeoutTask/OnceTimeoutTaskQueue.swift`
  - Only if any internal comments/doc comments still mention the old `stop` callback name.

## Verification Commands

```bash
rtk xcodebuild test -project Project/RYKit.xcodeproj -scheme RYKitTests -destination 'platform=macOS' -only-testing:RYKitTests/OnceTimeoutTaskTests BUILD_LIBRARY_FOR_DISTRIBUTION=NO
rtk xcodebuild test -project Project/RYKit.xcodeproj -scheme RYKitTests -destination 'platform=macOS' -only-testing:RYKitTests/OnceTimeoutTaskQueueTests BUILD_LIBRARY_FOR_DISTRIBUTION=NO
rtk xcodebuild test -project Project/RYKit.xcodeproj -scheme RYKitTests -destination 'platform=macOS' BUILD_LIBRARY_FOR_DISTRIBUTION=NO
rtk swift build
rtk proxy git diff --check
```

Expected final result: all commands pass. Normal Xcode tests without `BUILD_LIBRARY_FOR_DISTRIBUTION=NO` remain outside scope due the existing project-wide interface verification issue.

---

### Task 1: Rename Stop Callback To StopWhenExecuting

**Files:**
- Modify: `Project/RYKitTests/TimeoutTaskTests.swift`
- Modify: `Classes/Core/TimeoutTask/OnceTimeoutTask.swift`
- Modify: `README.md`

- [ ] **Step 1: Update tests to the new API name**

In `Project/RYKitTests/TimeoutTaskTests.swift`, replace every `stop:` label used for `OnceTimeoutTask` construction with `stopWhenExecuting:`.

Examples:

```swift
let task = OnceTimeoutTask<Int, TestError>(
    flag: "default-stop",
    executionTimeoutInterval: .seconds(10),
    stopTimeoutInterval: .milliseconds(100),
    execute: { _ in started.fulfill() },
    stopWhenExecuting: { stopped in
        stopped()
    }
)
```

and async:

```swift
let task = OnceTimeoutTask<Int, TestError>(
    flag: "async-default-stop",
    executionTimeoutInterval: .seconds(10),
    stopTimeoutInterval: .milliseconds(100),
    execute: {
        .success(1)
    },
    stopWhenExecuting: {}
)
```

In `README.md`, replace both TimeoutTask example labels:

```swift
stopWhenExecuting: { stopped in
    stopped()
}
```

- [ ] **Step 2: Run focused task tests and verify red failure**

```bash
rtk xcodebuild test -project Project/RYKit.xcodeproj -scheme RYKitTests -destination 'platform=macOS' -only-testing:RYKitTests/OnceTimeoutTaskTests BUILD_LIBRARY_FOR_DISTRIBUTION=NO
```

Expected: FAIL because the current initializer still uses `stop:` / `Stop`.

- [ ] **Step 3: Rename the typealias and initializer parameters**

In `Classes/Core/TimeoutTask/OnceTimeoutTask.swift`, change:

```swift
public typealias Stop = (@escaping Stopped) -> Void
private let stopAction: Stop
```

to:

```swift
public typealias StopWhenExecuting = (@escaping Stopped) -> Void
private let stopAction: StopWhenExecuting
```

Update callback initializer:

```swift
public init(
    flag: String,
    executionTimeoutInterval: DispatchTimeInterval?,
    stopTimeoutInterval: DispatchTimeInterval?,
    execute: @escaping (@escaping Completed) -> Void,
    stopWhenExecuting: @escaping StopWhenExecuting = { stopped in stopped() }
)
```

and assign:

```swift
self.stopAction = stopWhenExecuting
```

Update async initializer:

```swift
public convenience init(
    flag: String,
    executionTimeoutInterval: DispatchTimeInterval?,
    stopTimeoutInterval: DispatchTimeInterval?,
    execute: @escaping () async -> Result<T, E>,
    stopWhenExecuting: @escaping () async -> Void = {}
)
```

Bridge with:

```swift
let bridgedStop: StopWhenExecuting = { stopped in
    Task {
        await stopWhenExecuting()
        stopped()
    }
}
```

- [ ] **Step 4: Update doc comments to match the new name**

In `Classes/Core/TimeoutTask/OnceTimeoutTask.swift`, update comments so they refer to `StopWhenExecuting` / `stopWhenExecuting` instead of generic `Stop` / `stop` closure.

If `Classes/Core/TimeoutTask/OnceTimeoutTaskQueue.swift` comments mention the old stop callback name, update those references too.

- [ ] **Step 5: Run focused task tests**

```bash
rtk xcodebuild test -project Project/RYKit.xcodeproj -scheme RYKitTests -destination 'platform=macOS' -only-testing:RYKitTests/OnceTimeoutTaskTests BUILD_LIBRARY_FOR_DISTRIBUTION=NO
```

Expected: PASS.

- [ ] **Step 6: Commit Task 1**

```bash
rtk git add Classes/Core/TimeoutTask/OnceTimeoutTask.swift Project/RYKitTests/TimeoutTaskTests.swift README.md Classes/Core/TimeoutTask/OnceTimeoutTaskQueue.swift
rtk git commit -m "Rename timeout task stop callback" -m "The cooperative stop callback is now named StopWhenExecuting to make clear it only runs for executing tasks." -m "Constraint: Public task.stop() remains the only external interruption API" -m "Confidence: high" -m "Scope-risk: narrow" -m "Tested: xcodebuild OnceTimeoutTaskTests with BUILD_LIBRARY_FOR_DISTRIBUTION=NO"
```

---

### Task 2: Unify Direct Task Stop For Queued States

**Files:**
- Modify: `Project/RYKitTests/TimeoutTaskTests.swift`
- Modify: `Classes/Core/TimeoutTask/OnceTimeoutTask.swift`

- [ ] **Step 1: Add direct-stop failing tests**

In `Project/RYKitTests/TimeoutTaskTests.swift`, add these tests in `OnceTimeoutTaskTests` near the existing stop tests:

```swift
func test_stop_onUnstart_marksDoneStopWithoutCallingStopWhenExecuting() {
    let stopCalled = expectation(description: "stopWhenExecuting called")
    stopCalled.isInverted = true
    let task = OnceTimeoutTask<Int, TestError>(
        flag: "unstart-stop",
        executionTimeoutInterval: .seconds(10),
        stopTimeoutInterval: .milliseconds(100),
        execute: { _ in },
        stopWhenExecuting: { _ in
            stopCalled.fulfill()
        }
    )

    task.stop()

    wait(for: [stopCalled], timeout: 0.2)
    guard case .done(.stop) = task.state else {
        XCTFail("Expected done(stop), got \(task.state)")
        return
    }
}

func test_stop_onWaitingRestartStoppedTrue_marksDoneStopWithoutCallingStopWhenExecuting() {
    let stopCalled = expectation(description: "stopWhenExecuting called")
    stopCalled.isInverted = true
    let task = OnceTimeoutTask<Int, TestError>(
        flag: "restart-stop",
        executionTimeoutInterval: .seconds(10),
        stopTimeoutInterval: .milliseconds(100),
        execute: { _ in },
        stopWhenExecuting: { _ in
            stopCalled.fulfill()
        }
    )

    task.setWaitingRestartForTest(stopped: true)
    task.stop()

    wait(for: [stopCalled], timeout: 0.2)
    guard case .done(.stop) = task.state else {
        XCTFail("Expected done(stop), got \(task.state)")
        return
    }
}

func test_stop_onWaitingRestartStoppedFalse_doesNotCreateSecondStopFlow() {
    let stopCalled = expectation(description: "stopWhenExecuting called")
    stopCalled.isInverted = true
    let task = OnceTimeoutTask<Int, TestError>(
        flag: "restart-waiting",
        executionTimeoutInterval: .seconds(10),
        stopTimeoutInterval: .milliseconds(100),
        execute: { _ in },
        stopWhenExecuting: { _ in
            stopCalled.fulfill()
        }
    )

    task.setWaitingRestartForTest(stopped: false)
    task.stop()

    wait(for: [stopCalled], timeout: 0.2)
    guard case .waitingRestart(stopped: false) = task.state else {
        XCTFail("Expected waitingRestart(false), got \(task.state)")
        return
    }
}
```

- [ ] **Step 2: Run focused task tests and verify they fail**

```bash
rtk xcodebuild test -project Project/RYKit.xcodeproj -scheme RYKitTests -destination 'platform=macOS' -only-testing:RYKitTests/OnceTimeoutTaskTests BUILD_LIBRARY_FOR_DISTRIBUTION=NO
```

Expected: FAIL because current `task.stop()` still no-ops for `.unstart` and `.waitingRestart(stopped: true)`.

- [ ] **Step 3: Add direct-stop fast path**

In `Classes/Core/TimeoutTask/OnceTimeoutTask.swift`, update `public func stop()` to:

```swift
public func stop() {
    if let doneType = stopWhileQueued() {
        notifyDone(doneType)
        return
    }
    guard let request = makeStopRequest(timeoutQueue: .global(qos: .userInitiated), onStopped: { [weak self] in
        self?.notifyDone(.stop)
    }) else {
        return
    }
    request()
}
```

Rename the current queue helper from `stopFromQueue()` to `stopWhileQueued()`:

```swift
@discardableResult
func stopWhileQueued() -> DoneType? {
    lock.lock()
    switch currentState {
    case .unstart, .waitingRestart(stopped: true):
        currentState = .done(.stop)
        runGeneration &+= 1
        stopGeneration &+= 1
        executionTimeoutItem = nil
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

Update any queue call sites to the new internal helper name.

- [ ] **Step 4: Run focused task and queue tests**

```bash
rtk xcodebuild test -project Project/RYKit.xcodeproj -scheme RYKitTests -destination 'platform=macOS' -only-testing:RYKitTests/OnceTimeoutTaskTests BUILD_LIBRARY_FOR_DISTRIBUTION=NO
rtk xcodebuild test -project Project/RYKit.xcodeproj -scheme RYKitTests -destination 'platform=macOS' -only-testing:RYKitTests/OnceTimeoutTaskQueueTests BUILD_LIBRARY_FOR_DISTRIBUTION=NO
```

Expected: PASS.

- [ ] **Step 5: Commit Task 2**

```bash
rtk git add Classes/Core/TimeoutTask/OnceTimeoutTask.swift Classes/Core/TimeoutTask/OnceTimeoutTaskQueue.swift Project/RYKitTests/TimeoutTaskTests.swift
rtk git commit -m "Unify direct timeout task stop" -m "Direct task.stop() now uses the same immediate stop semantics as queue stop for queued non-executing states while still reserving stopWhenExecuting for executing tasks." -m "Constraint: stopWhenExecuting is never called for unstart or waitingRestart(stopped: true)" -m "Confidence: high" -m "Scope-risk: moderate" -m "Tested: focused task and queue tests with BUILD_LIBRARY_FOR_DISTRIBUTION=NO"
```

---

### Task 3: Final Verification

**Files:**
- Verify: `Classes/Core/TimeoutTask/OnceTimeoutTask.swift`
- Verify: `Classes/Core/TimeoutTask/OnceTimeoutTaskQueue.swift`
- Verify: `Project/RYKitTests/TimeoutTaskTests.swift`
- Verify: `README.md`

- [ ] **Step 1: Run cancel scan**

```bash
rtk rg -n "cancel|Cancel|cancelAll|\\.cancel|cancelFromQueue|transitionToCancel" Classes/Core/TimeoutTask Project/RYKitTests/TimeoutTaskTests.swift README.md
```

Expected:
- No matches in `Classes/Core/TimeoutTask`.
- No matches in `Project/RYKitTests/TimeoutTaskTests.swift` except Combine `cancellables`.
- README may still contain unrelated `cancelIfRequesting` or Combine `cancellables`; those are acceptable.

- [ ] **Step 2: Run focused task tests**

```bash
rtk xcodebuild test -project Project/RYKit.xcodeproj -scheme RYKitTests -destination 'platform=macOS' -only-testing:RYKitTests/OnceTimeoutTaskTests BUILD_LIBRARY_FOR_DISTRIBUTION=NO
```

Expected: PASS.

- [ ] **Step 3: Run focused queue tests**

```bash
rtk xcodebuild test -project Project/RYKit.xcodeproj -scheme RYKitTests -destination 'platform=macOS' -only-testing:RYKitTests/OnceTimeoutTaskQueueTests BUILD_LIBRARY_FOR_DISTRIBUTION=NO
```

Expected: PASS.

- [ ] **Step 4: Run full fallback Xcode suite**

```bash
rtk xcodebuild test -project Project/RYKit.xcodeproj -scheme RYKitTests -destination 'platform=macOS' BUILD_LIBRARY_FOR_DISTRIBUTION=NO
```

Expected: PASS.

- [ ] **Step 5: Run SwiftPM build and diff hygiene**

```bash
rtk swift build
rtk proxy git diff --check
```

Expected: PASS.

- [ ] **Step 6: Commit final cleanup if needed**

Use only if verification requires small follow-up fixes:

```bash
rtk git add README.md Classes/Core/TimeoutTask/OnceTimeoutTask.swift Classes/Core/TimeoutTask/OnceTimeoutTaskQueue.swift Project/RYKitTests/TimeoutTaskTests.swift
rtk git commit -m "Finalize stop-only timeout task cleanup" -m "The timeout task API and tests now use StopWhenExecuting naming and unified stop semantics consistently." -m "Confidence: high" -m "Scope-risk: narrow" -m "Tested: focused task and queue tests, full fallback Xcode test suite, swift build, diff check"
```

