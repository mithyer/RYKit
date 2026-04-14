# OnceTimeoutTask Optional Stop And Timeouts Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Allow `OnceTimeoutTask` to disable stop handling and timeout scheduling with explicit `nil` values.

**Architecture:** `OnceTimeoutTask` stores optional execution/stop timeout intervals and optional stop closures. It exposes an internal `isStoppable` gate so `OnceTimeoutTaskQueue` can downgrade stop-based preemption strategies to wait-current-completion for non-stoppable current tasks.

**Tech Stack:** Swift, Foundation, Combine, XCTest, existing `UnfairLock`.

---

## File Structure

- Modify `Classes/Core/TimeoutTask/OnceTimeoutTask.swift`
  - Make `executionTimeoutInterval`, `stopTimeoutInterval`, and stop action optional; skip timeout work item scheduling when nil; make public stop a no-op when stop is nil; add internal `isStoppable`.
- Modify `Classes/Core/TimeoutTask/OnceTimeoutTaskQueue.swift`
  - Check `current.task.isStoppable` before attempting stop/restart preemption. Non-stoppable current tasks keep wait-current-completion behavior for every preemption strategy.
- Modify `Project/RYKitTests/TimeoutTaskTests.swift`
  - Add optional timeout/stop task tests and non-stoppable preemption tests. Update existing async initializer calls for optional stop.
- Modify `README.md`
  - Update TimeoutTask examples to show explicit optional timeout/stop API.

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

### Task 1: Add Optional Stop And Timeout To OnceTimeoutTask

**Files:**
- Modify: `Project/RYKitTests/TimeoutTaskTests.swift`
- Modify: `Classes/Core/TimeoutTask/OnceTimeoutTask.swift`

- [ ] **Step 1: Add task-level failing tests**

In `Project/RYKitTests/TimeoutTaskTests.swift`, inside `OnceTimeoutTaskTests`, add these tests after `test_executionTimeout_updatesState`:

```swift
func test_nilExecutionTimeout_doesNotTimeoutNonCompletingTask() {
    let finished = expectation(description: "finished")
    finished.isInverted = true
    let task = OnceTimeoutTask<Int, TestError>(
        flag: "no-execution-timeout",
        executionTimeoutInterval: nil,
        stopTimeoutInterval: .milliseconds(100),
        execute: { _ in },
        stop: { stopped in stopped() }
    )
    task.onDone = { _ in finished.fulfill() }

    task.perform(by: .global(), timeoutQueue: .global())
    wait(for: [finished], timeout: 0.2)

    if case .executing = task.state {
    } else {
        XCTFail("Expected executing, got \(task.state)")
    }
}

func test_nilStopTimeout_waitsForStoppedWithoutFallback() {
    let stopCalled = expectation(description: "stop called")
    let stoppedBeforeCallback = expectation(description: "stopped before callback")
    stoppedBeforeCallback.isInverted = true
    let stoppedAfterCallback = expectation(description: "stopped after callback")
    var capturedStopped: OnceTimeoutTask<Int, TestError>.Stopped?

    let task = OnceTimeoutTask<Int, TestError>(
        flag: "no-stop-timeout",
        executionTimeoutInterval: .seconds(10),
        stopTimeoutInterval: nil,
        execute: { _ in },
        stop: { stopped in
            capturedStopped = stopped
            stopCalled.fulfill()
        }
    )

    task.perform(by: .global(), timeoutQueue: .global())
    let request = task.makeStopRequest(timeoutQueue: .global()) {
        stoppedAfterCallback.fulfill()
        stoppedBeforeCallback.fulfill()
    }
    request?()

    wait(for: [stopCalled], timeout: 1.0)
    wait(for: [stoppedBeforeCallback], timeout: 0.2)
    capturedStopped?()
    wait(for: [stoppedAfterCallback], timeout: 1.0)
}

func test_stopNil_publicStopDoesNothing() {
    let stopFinished = expectation(description: "stop finished")
    stopFinished.isInverted = true
    let task = OnceTimeoutTask<Int, TestError>(
        flag: "non-stoppable",
        executionTimeoutInterval: .seconds(10),
        stopTimeoutInterval: .milliseconds(100),
        execute: { _ in },
        stop: nil
    )
    task.onDone = { _ in stopFinished.fulfill() }

    task.perform(by: .global(), timeoutQueue: .global())
    task.stop()

    wait(for: [stopFinished], timeout: 0.2)
    if case .executing = task.state {
    } else {
        XCTFail("Expected executing, got \(task.state)")
    }
}

func test_asyncInit_acceptsNilStop() async throws {
    let task = OnceTimeoutTask<Int, TestError>(
        flag: "async-no-stop",
        executionTimeoutInterval: .seconds(10),
        stopTimeoutInterval: nil,
        execute: {
            .success(99)
        },
        stop: nil
    )

    task.perform(by: .global(), timeoutQueue: .global())
    try await Task.sleep(nanoseconds: 100_000_000)

    assertCompletedSuccess(doneType(of: task), equals: 99)
}
```

- [ ] **Step 2: Run task tests and verify they fail**

```bash
rtk xcodebuild test -project Project/RYKit.xcodeproj -scheme RYKitTests -destination 'platform=macOS' -only-testing:RYKitTests/OnceTimeoutTaskTests BUILD_LIBRARY_FOR_DISTRIBUTION=NO
```

Expected: FAIL because initializer parameters and stored timeout/stop properties are not optional yet.

- [ ] **Step 3: Make task stored values optional**

In `Classes/Core/TimeoutTask/OnceTimeoutTask.swift`, change:

```swift
let executionTimeoutInterval: DispatchTimeInterval
let stopTimeoutInterval: DispatchTimeInterval
private let stopAction: Stop
```

to:

```swift
let executionTimeoutInterval: DispatchTimeInterval?
let stopTimeoutInterval: DispatchTimeInterval?
private let stopAction: Stop?
```

Add:

```swift
var isStoppable: Bool {
    stopAction != nil
}
```

- [ ] **Step 4: Make callback initializer optional**

Change the callback initializer signature to:

```swift
public init(
    flag: String,
    executionTimeoutInterval: DispatchTimeInterval?,
    stopTimeoutInterval: DispatchTimeInterval?,
    execute: @escaping (@escaping Completed) -> Void,
    stop: Stop?
)
```

Keep assignments the same.

- [ ] **Step 5: Make async initializer optional**

Change the async initializer signature to:

```swift
public convenience init(
    flag: String,
    executionTimeoutInterval: DispatchTimeInterval?,
    stopTimeoutInterval: DispatchTimeInterval?,
    execute: @escaping () async -> Result<T, E>,
    stop: (() async -> Void)?
)
```

Change the bridged stop argument to:

```swift
let bridgedStop: Stop? = stop.map { stop in
    { stopped in
        Task {
            await stop()
            stopped()
        }
    }
}
```

Then pass `stop: bridgedStop` to the callback initializer.

- [ ] **Step 6: Skip nil execution timeout scheduling**

In `perform(by:timeoutQueue:)`, replace the timeout item creation/scheduling with optional scheduling:

```swift
let timeoutItem: DispatchWorkItem?
if executionTimeoutInterval != nil {
    timeoutItem = DispatchWorkItem { [weak self] in
        self?.finish(with: .executionTimeout, notify: true, runGeneration: generation)
    }
} else {
    timeoutItem = nil
}
```

After unlocking, replace unconditional scheduling with:

```swift
if let timeoutItem, let interval = executionTimeoutInterval {
    timeoutQueue.asyncAfter(deadline: .now() + interval, execute: timeoutItem)
}
```

- [ ] **Step 7: Make stop no-op when stop is nil**

In the private stop request helper, after the executing-state guard and before incrementing stop generation, add:

```swift
guard let stopAction else {
    lock.unlock()
    return nil
}
```

Adjust existing `let stopAction = self.stopAction` usage so it is non-optional after the guard.

- [ ] **Step 8: Skip nil stop timeout scheduling**

In the private stop request helper, replace:

```swift
if case .never = interval {
} else {
    timeoutQueue.asyncAfter(deadline: .now() + interval, execute: stopTimeoutItem)
}
```

with:

```swift
if let interval, case .never = interval {
} else if let interval {
    timeoutQueue.asyncAfter(deadline: .now() + interval, execute: stopTimeoutItem)
}
```

- [ ] **Step 9: Run task tests**

```bash
rtk xcodebuild test -project Project/RYKit.xcodeproj -scheme RYKitTests -destination 'platform=macOS' -only-testing:RYKitTests/OnceTimeoutTaskTests BUILD_LIBRARY_FOR_DISTRIBUTION=NO
```

Expected: PASS.

- [ ] **Step 10: Commit Task 1**

```bash
rtk git add Classes/Core/TimeoutTask/OnceTimeoutTask.swift Project/RYKitTests/TimeoutTaskTests.swift
rtk git commit -m "Allow optional task stop and timeouts" -m "Timeout tasks can now explicitly disable execution timeout, stop timeout, or stop handling while preserving existing stoppable behavior." -m "Constraint: nil stop makes public stop a no-op" -m "Confidence: high" -m "Scope-risk: moderate" -m "Tested: xcodebuild OnceTimeoutTaskTests with BUILD_LIBRARY_FOR_DISTRIBUTION=NO"
```

---

### Task 2: Downgrade Queue Preemption For Non-Stoppable Tasks

**Files:**
- Modify: `Project/RYKitTests/TimeoutTaskTests.swift`
- Modify: `Classes/Core/TimeoutTask/OnceTimeoutTaskQueue.swift`

- [ ] **Step 1: Add non-stoppable queue tests**

In `Project/RYKitTests/TimeoutTaskTests.swift`, inside `OnceTimeoutTaskQueueTests`, add these tests near the existing preemption tests:

```swift
func test_stopCurrentAndDiscard_nonStoppableCurrentWaitsForCompletion() {
    let queue = OnceTimeoutTaskQueue<Int, TestError>(executeQueue: .global())
    let currentStarted = expectation(description: "current started")
    let allowCurrentToFinish = DispatchSemaphore(value: 0)
    let allFinished = expectation(description: "all finished")
    allFinished.expectedFulfillmentCount = 2
    var executionOrder: [String] = []
    let lock = NSLock()

    queue.taskDidFinish
        .sink { _ in allFinished.fulfill() }
        .store(in: &cancellables)

    let current = OnceTimeoutTask<Int, TestError>(
        flag: "current",
        executionTimeoutInterval: nil,
        stopTimeoutInterval: nil,
        execute: { completed in
            lock.lock()
            executionOrder.append("current")
            lock.unlock()
            currentStarted.fulfill()
            allowCurrentToFinish.wait()
            completed(.success(1))
        },
        stop: nil
    )
    let high = makeTask(flag: "high", value: 2, onExecute: {
        lock.lock()
        executionOrder.append("high")
        lock.unlock()
    })

    queue.addTask(current, priority: 0)
    wait(for: [currentStarted], timeout: 1.0)
    queue.addTask(high, priority: 10, preemptionStrategy: .stopCurrentAndDiscard)
    Thread.sleep(forTimeInterval: 0.2)

    XCTAssertEqual(executionOrder, ["current"])

    allowCurrentToFinish.signal()
    wait(for: [allFinished], timeout: 2.0)
    XCTAssertEqual(executionOrder, ["current", "high"])
}

func test_stopCurrentAndRequeue_nonStoppableCurrentWaitsForCompletion() {
    let queue = OnceTimeoutTaskQueue<Int, TestError>(executeQueue: .global())
    let currentStarted = expectation(description: "current started")
    let allowCurrentToFinish = DispatchSemaphore(value: 0)
    let allFinished = expectation(description: "all finished")
    allFinished.expectedFulfillmentCount = 2
    var executionOrder: [String] = []
    let lock = NSLock()

    queue.taskDidFinish
        .sink { _ in allFinished.fulfill() }
        .store(in: &cancellables)

    let current = OnceTimeoutTask<Int, TestError>(
        flag: "current",
        executionTimeoutInterval: nil,
        stopTimeoutInterval: nil,
        execute: { completed in
            lock.lock()
            executionOrder.append("current")
            lock.unlock()
            currentStarted.fulfill()
            allowCurrentToFinish.wait()
            completed(.success(1))
        },
        stop: nil
    )
    let high = makeTask(flag: "high", value: 2, onExecute: {
        lock.lock()
        executionOrder.append("high")
        lock.unlock()
    })

    queue.addTask(current, priority: 0)
    wait(for: [currentStarted], timeout: 1.0)
    queue.addTask(high, priority: 10, preemptionStrategy: .stopCurrentAndRequeue)
    Thread.sleep(forTimeInterval: 0.2)

    XCTAssertEqual(executionOrder, ["current"])

    allowCurrentToFinish.signal()
    wait(for: [allFinished], timeout: 2.0)
    XCTAssertEqual(executionOrder, ["current", "high"])
}
```

- [ ] **Step 2: Run queue tests and verify they fail**

```bash
rtk xcodebuild test -project Project/RYKit.xcodeproj -scheme RYKitTests -destination 'platform=macOS' -only-testing:RYKitTests/OnceTimeoutTaskQueueTests BUILD_LIBRARY_FOR_DISTRIBUTION=NO
```

Expected: FAIL because queue preemption still attempts stop-based strategies without checking `isStoppable`.

- [ ] **Step 3: Downgrade stop strategies when current is not stoppable**

In `Classes/Core/TimeoutTask/OnceTimeoutTaskQueue.swift`, inside `addTask`, update the high-priority branch:

```swift
if let current, item.priority > current.priority {
    insert(item)
    let effectiveStrategy = current.task.isStoppable ? strategy : .waitCurrentCompletion
    switch effectiveStrategy {
    case .waitCurrentCompletion:
        stopRequest = nil
    case .stopCurrentAndDiscard:
        stopRequest = prepareStopLocked(disposition: .discard)
    case .stopCurrentAndRequeue:
        stopRequest = prepareStopLocked(disposition: .requeue)
    }
} else {
    insert(item)
    stopRequest = nil
}
```

- [ ] **Step 4: Run queue tests**

```bash
rtk xcodebuild test -project Project/RYKit.xcodeproj -scheme RYKitTests -destination 'platform=macOS' -only-testing:RYKitTests/OnceTimeoutTaskQueueTests BUILD_LIBRARY_FOR_DISTRIBUTION=NO
```

Expected: PASS.

- [ ] **Step 5: Commit Task 2**

```bash
rtk git add Classes/Core/TimeoutTask/OnceTimeoutTaskQueue.swift Project/RYKitTests/TimeoutTaskTests.swift
rtk git commit -m "Wait on non-stoppable preemption" -m "Queue preemption now treats nil-stop current tasks as non-stoppable and falls back to wait-current-completion for all stop-based strategies." -m "Constraint: nil execution timeout plus nil stop can hold the queue indefinitely" -m "Confidence: high" -m "Scope-risk: narrow" -m "Tested: xcodebuild OnceTimeoutTaskQueueTests with BUILD_LIBRARY_FOR_DISTRIBUTION=NO"
```

---

### Task 3: Update README Examples And Run Final Verification

**Files:**
- Modify: `README.md`

- [ ] **Step 1: Update README examples**

In both English and Chinese TimeoutTask snippets, keep the stoppable example explicit:

```swift
let task = OnceTimeoutTask<String, Error>(
    flag: "load-profile",
    executionTimeoutInterval: .seconds(3),
    stopTimeoutInterval: .seconds(1),
    execute: { complete in
        complete(.success("ok"))
    },
    stop: { stopped in
        stopped()
    }
)
```

Add a short no-timeout/non-stoppable snippet after the queue example in both sections:

```swift
let persistentTask = OnceTimeoutTask<String, Error>(
    flag: "persistent",
    executionTimeoutInterval: nil,
    stopTimeoutInterval: nil,
    execute: { _ in
        // Complete later, or keep running.
    },
    stop: nil
)
queue.addTask(persistentTask, priority: 1)
```

- [ ] **Step 2: Run removed API scan**

```bash
rtk rg -n "timeoutInterval|done:|\\.timeout" README.md Project/RYKitTests/TimeoutTaskTests.swift Classes/Core/TimeoutTask
```

Expected: no removed public API usage. Matches for internal names like `timeoutQueue` are acceptable.

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
rtk git add README.md
rtk git commit -m "Document optional timeout task stop" -m "README examples now show explicit nil timeout and nil stop usage for persistent non-stoppable timeout tasks." -m "Confidence: high" -m "Scope-risk: narrow" -m "Tested: focused task and queue tests, full fallback Xcode test suite, swift build, diff check"
```
