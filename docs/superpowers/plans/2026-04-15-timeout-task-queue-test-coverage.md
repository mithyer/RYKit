# Timeout Task Queue Test Coverage Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add comprehensive unit coverage for `OnceTimeoutTask` and `OnceTimeoutTaskQueue`, then make only the smallest production-code changes required by newly approved edge-case tests.

**Architecture:** Keep nearly all work inside `Project/RYKitTests/TimeoutTaskTests.swift` by adding local helpers plus focused tests for task state transitions, stop/idempotency races, queue ownership visibility, and preemption boundaries. Limit production changes to `OnceTimeoutTaskQueue` bookkeeping fixes uncovered by the new tests and a narrow internal `isStoppable` seam in `OnceTimeoutTask` so the queue's existing non-stoppable fallback branch can be exercised.

**Tech Stack:** Swift, XCTest, Combine, Foundation, xcodebuild

---

## File Structure

- Modify `Project/RYKitTests/TimeoutTaskTests.swift`
  - Add local test helpers.
  - Add `OnceTimeoutTask` state-transition and race/idempotency tests.
  - Add `OnceTimeoutTaskQueue` ownership, `allTasks`, and scheduling/preemption edge-case tests.
- Modify `Classes/Core/TimeoutTask/OnceTimeoutTaskQueue.swift`
  - Prevent duplicate queue ownership of the same task instance.
  - Prevent stop-based preemption from firing while the queue is paused.
- Modify `Classes/Core/TimeoutTask/OnceTimeoutTask.swift`
  - Add a narrow internal initializer seam so tests can construct a non-stoppable task and cover the queue's existing fallback behavior.

## Verification Commands

```bash
rtk xcodebuild test -project Project/RYKit.xcodeproj -scheme RYKitTests -destination 'platform=macOS' -only-testing:RYKitTests/OnceTimeoutTaskTests BUILD_LIBRARY_FOR_DISTRIBUTION=NO
rtk xcodebuild test -project Project/RYKit.xcodeproj -scheme RYKitTests -destination 'platform=macOS' -only-testing:RYKitTests/OnceTimeoutTaskQueueTests BUILD_LIBRARY_FOR_DISTRIBUTION=NO
rtk xcodebuild test -project Project/RYKit.xcodeproj -scheme RYKitTests -destination 'platform=macOS' BUILD_LIBRARY_FOR_DISTRIBUTION=NO
rtk swift build
rtk proxy git diff --check
```

Expected final result: all commands pass. Running Xcode tests without `BUILD_LIBRARY_FOR_DISTRIBUTION=NO` is outside scope because of the existing project-wide swiftinterface verification issue.

---

### Task 1: Add Test Helpers And `OnceTimeoutTask` Transition Coverage

**Files:**
- Modify: `Project/RYKitTests/TimeoutTaskTests.swift`
- Test: `Project/RYKitTests/TimeoutTaskTests.swift`

- [ ] **Step 1: Add file-local polling and event-recording helpers**

Add these helpers near the top of `Project/RYKitTests/TimeoutTaskTests.swift`, below imports and above the test case declarations:

```swift
private func waitUntil(
    timeout: TimeInterval = 1.0,
    pollInterval: TimeInterval = 0.01,
    file: StaticString = #filePath,
    line: UInt = #line,
    _ condition: () -> Bool
) {
    let deadline = Date().addingTimeInterval(timeout)
    while Date() < deadline {
        if condition() {
            return
        }
        Thread.sleep(forTimeInterval: pollInterval)
    }
    XCTFail("Timed out waiting for condition", file: file, line: line)
}

private final class FinishEventRecorder<T, E: Error> {
    typealias Queue = OnceTimeoutTaskQueue<T, E>

    private let lock = NSLock()
    private var storedEvents: [Queue.TaskFinishEvent] = []
    private var cancellable: AnyCancellable?

    init(queue: Queue) {
        cancellable = queue.taskDidFinish.sink { [weak self] event in
            self?.lock.lock()
            self?.storedEvents.append(event)
            self?.lock.unlock()
        }
    }

    var events: [Queue.TaskFinishEvent] {
        lock.lock()
        defer { lock.unlock() }
        return storedEvents
    }

    var flags: [String] {
        events.map(\.flag)
    }
}
```

- [ ] **Step 2: Add new `OnceTimeoutTask` transition tests**

Append these tests inside `final class OnceTimeoutTaskTests: XCTestCase` near the other task state tests:

```swift
func test_perform_whileExecuting_doesNotStartSecondRun() {
    let firstRunStarted = expectation(description: "first run started")
    let secondRunStarted = expectation(description: "second run started")
    secondRunStarted.isInverted = true
    let allowCompletion = DispatchSemaphore(value: 0)
    let executeQueue = DispatchQueue(label: "OnceTimeoutTaskTests.performWhileExecuting")
    let lock = NSLock()
    var runCount = 0

    let task = OnceTimeoutTask<Int, TestError>(
        flag: "double-perform-executing",
        executionTimeoutInterval: .seconds(10),
        stopTimeoutInterval: .milliseconds(100),
        execute: { completed in
            lock.lock()
            runCount += 1
            let currentRun = runCount
            lock.unlock()

            if currentRun == 1 {
                firstRunStarted.fulfill()
            } else {
                secondRunStarted.fulfill()
            }

            allowCompletion.wait()
            completed(.success(currentRun))
        },
        stopWhenExecuting: { stopped in stopped() }
    )

    task.perform(by: executeQueue, timeoutQueue: .global())
    wait(for: [firstRunStarted], timeout: 1.0)
    task.perform(by: executeQueue, timeoutQueue: .global())

    wait(for: [secondRunStarted], timeout: 0.2)
    lock.lock()
    let finalRunCount = runCount
    lock.unlock()
    XCTAssertEqual(finalRunCount, 1)

    allowCompletion.signal()
}

func test_perform_whenDone_doesNotRestartTask() {
    let firstCompletion = expectation(description: "first completion")
    let secondRunStarted = expectation(description: "second run started")
    secondRunStarted.isInverted = true
    let executeQueue = DispatchQueue(label: "OnceTimeoutTaskTests.performWhenDone")
    let lock = NSLock()
    var runCount = 0

    let task = OnceTimeoutTask<Int, TestError>(
        flag: "done-perform",
        executionTimeoutInterval: .seconds(10),
        stopTimeoutInterval: .milliseconds(100),
        execute: { completed in
            lock.lock()
            runCount += 1
            let currentRun = runCount
            lock.unlock()

            if currentRun == 1 {
                completed(.success(1))
                firstCompletion.fulfill()
            } else {
                secondRunStarted.fulfill()
                completed(.success(2))
            }
        },
        stopWhenExecuting: { stopped in stopped() }
    )

    task.perform(by: executeQueue, timeoutQueue: .global())
    wait(for: [firstCompletion], timeout: 1.0)
    task.perform(by: executeQueue, timeoutQueue: .global())

    wait(for: [secondRunStarted], timeout: 0.2)
    lock.lock()
    let finalRunCount = runCount
    lock.unlock()
    XCTAssertEqual(finalRunCount, 1)
}

func test_stopWhileQueued_returnsStopOnlyFromStartableQueuedStates() {
    let unstarted = OnceTimeoutTask<Int, TestError>(
        flag: "queued-unstart",
        executionTimeoutInterval: .seconds(10),
        stopTimeoutInterval: .milliseconds(100),
        execute: { _ in },
        stopWhenExecuting: { stopped in stopped() }
    )
    XCTAssertEqual(unstarted.stopWhileQueued(), .stop)
    guard case .done(.stop) = unstarted.state else {
        XCTFail("Expected done(stop), got \(unstarted.state)")
        return
    }

    let restartReady = OnceTimeoutTask<Int, TestError>(
        flag: "queued-restart-ready",
        executionTimeoutInterval: .seconds(10),
        stopTimeoutInterval: .milliseconds(100),
        execute: { _ in },
        stopWhenExecuting: { stopped in stopped() }
    )
    restartReady.setWaitingRestartForTest(stopped: true)
    XCTAssertEqual(restartReady.stopWhileQueued(), .stop)
    guard case .done(.stop) = restartReady.state else {
        XCTFail("Expected done(stop), got \(restartReady.state)")
        return
    }
}

func test_stopWhileQueued_returnsNilFromExecutingWaitingRestartFalseAndDone() {
    let executingStarted = expectation(description: "executing started")
    let executeQueue = DispatchQueue(label: "OnceTimeoutTaskTests.stopWhileQueued.nil")
    let executing = OnceTimeoutTask<Int, TestError>(
        flag: "executing",
        executionTimeoutInterval: .seconds(10),
        stopTimeoutInterval: .milliseconds(100),
        execute: { _ in executingStarted.fulfill() },
        stopWhenExecuting: { stopped in stopped() }
    )
    executing.perform(by: executeQueue, timeoutQueue: .global())
    wait(for: [executingStarted], timeout: 1.0)
    XCTAssertNil(executing.stopWhileQueued())

    let waitingRestart = OnceTimeoutTask<Int, TestError>(
        flag: "waiting-restart",
        executionTimeoutInterval: .seconds(10),
        stopTimeoutInterval: .milliseconds(100),
        execute: { _ in },
        stopWhenExecuting: { stopped in stopped() }
    )
    waitingRestart.setWaitingRestartForTest(stopped: false)
    XCTAssertNil(waitingRestart.stopWhileQueued())

    let doneTask = OnceTimeoutTask<Int, TestError>(
        flag: "done",
        executionTimeoutInterval: .seconds(10),
        stopTimeoutInterval: .milliseconds(100),
        execute: { _ in },
        stopWhenExecuting: { stopped in stopped() }
    )
    XCTAssertEqual(doneTask.stopWhileQueued(), .stop)
    XCTAssertNil(doneTask.stopWhileQueued())
}

func test_makeStopRequest_returnsNilWhenTaskIsNotExecuting() {
    let states: [(String, (OnceTimeoutTask<Int, TestError>) -> Void)] = [
        ("unstart", { _ in }),
        ("waitingRestart(true)", { $0.setWaitingRestartForTest(stopped: true) }),
        ("waitingRestart(false)", { $0.setWaitingRestartForTest(stopped: false) }),
        ("done(stop)", { task in _ = task.stopWhileQueued() })
    ]

    for (name, configure) in states {
        let task = OnceTimeoutTask<Int, TestError>(
            flag: name,
            executionTimeoutInterval: .seconds(10),
            stopTimeoutInterval: .milliseconds(100),
            execute: { _ in },
            stopWhenExecuting: { stopped in stopped() }
        )
        configure(task)
        XCTAssertNil(
            task.makeStopRequest(timeoutQueue: .global(), onStopped: {}),
            "Expected nil makeStopRequest result for \(name)"
        )
    }
}

func test_makeRestartStopRequest_returnsNilWhenTaskIsNotExecuting() {
    let states: [(String, (OnceTimeoutTask<Int, TestError>) -> Void)] = [
        ("unstart", { _ in }),
        ("waitingRestart(true)", { $0.setWaitingRestartForTest(stopped: true) }),
        ("waitingRestart(false)", { $0.setWaitingRestartForTest(stopped: false) }),
        ("done(stop)", { task in _ = task.stopWhileQueued() })
    ]

    for (name, configure) in states {
        let task = OnceTimeoutTask<Int, TestError>(
            flag: name,
            executionTimeoutInterval: .seconds(10),
            stopTimeoutInterval: .milliseconds(100),
            execute: { _ in },
            stopWhenExecuting: { stopped in stopped() }
        )
        configure(task)
        XCTAssertNil(
            task.makeRestartStopRequest(timeoutQueue: .global(), onStopped: {}),
            "Expected nil makeRestartStopRequest result for \(name)"
        )
    }
}

func test_makeRestartStopRequest_stopTimeoutMarksWaitingRestartStoppedTrue() {
    let started = expectation(description: "started")
    let restartStopFinished = expectation(description: "restart stop finished")
    let executeQueue = DispatchQueue(label: "OnceTimeoutTaskTests.restartStopTimeout")

    let task = OnceTimeoutTask<Int, TestError>(
        flag: "restart-timeout",
        executionTimeoutInterval: .seconds(10),
        stopTimeoutInterval: .milliseconds(80),
        execute: { _ in started.fulfill() },
        stopWhenExecuting: { _ in }
    )

    task.perform(by: executeQueue, timeoutQueue: .global())
    wait(for: [started], timeout: 1.0)

    let request = task.makeRestartStopRequest(timeoutQueue: .global()) {
        restartStopFinished.fulfill()
    }
    XCTAssertNotNil(request)
    request?()

    guard case .waitingRestart(stopped: false) = task.state else {
        XCTFail("Expected waitingRestart(false), got \(task.state)")
        return
    }

    wait(for: [restartStopFinished], timeout: 1.0)
    guard case .waitingRestart(stopped: true) = task.state else {
        XCTFail("Expected waitingRestart(true), got \(task.state)")
        return
    }
}
```

- [ ] **Step 3: Run focused task tests and confirm they pass**

Run:

```bash
rtk xcodebuild test -project Project/RYKit.xcodeproj -scheme RYKitTests -destination 'platform=macOS' -only-testing:RYKitTests/OnceTimeoutTaskTests BUILD_LIBRARY_FOR_DISTRIBUTION=NO
```

Expected: PASS. These cases lock existing task-state semantics and should not require production changes.

- [ ] **Step 4: Commit Task 1**

```bash
rtk git add Project/RYKitTests/TimeoutTaskTests.swift
rtk git commit -m "Add timeout task transition coverage" -m "Cover perform guards, stopWhileQueued boundaries, and restart-stop timeout semantics." -m "Tested: xcodebuild OnceTimeoutTaskTests BUILD_LIBRARY_FOR_DISTRIBUTION=NO"
```

---

### Task 2: Add `OnceTimeoutTask` Race And Idempotency Coverage

**Files:**
- Modify: `Project/RYKitTests/TimeoutTaskTests.swift`
- Test: `Project/RYKitTests/TimeoutTaskTests.swift`

- [ ] **Step 1: Add duplicate-signal and stale-signal tests**

Append these tests inside `OnceTimeoutTaskTests` after the transition tests:

```swift
func test_stop_twiceWhileExecuting_callsStopClosureOnceAndNotifiesOnce() {
    let started = expectation(description: "started")
    let stopFinished = expectation(description: "stop finished")
    let executeQueue = DispatchQueue(label: "OnceTimeoutTaskTests.stopTwice")
    let lock = NSLock()
    var stopCallCount = 0
    var doneCount = 0
    var capturedStopped: OnceTimeoutTask<Int, TestError>.Stopped?

    let task = OnceTimeoutTask<Int, TestError>(
        flag: "stop-twice",
        executionTimeoutInterval: .seconds(10),
        stopTimeoutInterval: .seconds(1),
        execute: { _ in started.fulfill() },
        stopWhenExecuting: { stopped in
            lock.lock()
            stopCallCount += 1
            capturedStopped = stopped
            lock.unlock()
        }
    )
    task.onDone = { doneType in
        guard case .stop = doneType else { return }
        lock.lock()
        doneCount += 1
        lock.unlock()
        stopFinished.fulfill()
    }

    task.perform(by: executeQueue, timeoutQueue: .global())
    wait(for: [started], timeout: 1.0)
    task.stop()
    task.stop()

    waitUntil {
        lock.lock()
        defer { lock.unlock() }
        return stopCallCount == 1 && capturedStopped != nil
    }

    capturedStopped?()
    wait(for: [stopFinished], timeout: 1.0)

    lock.lock()
    let finalStopCallCount = stopCallCount
    let finalDoneCount = doneCount
    lock.unlock()
    XCTAssertEqual(finalStopCallCount, 1)
    XCTAssertEqual(finalDoneCount, 1)
}

func test_makeStopRequest_stoppedCallbackTwice_finishesOnlyOnce() {
    let started = expectation(description: "started")
    let stopFinished = expectation(description: "stop finished")
    let executeQueue = DispatchQueue(label: "OnceTimeoutTaskTests.stopCallbackTwice")
    let lock = NSLock()
    var finishCount = 0
    var capturedStopped: OnceTimeoutTask<Int, TestError>.Stopped?

    let task = OnceTimeoutTask<Int, TestError>(
        flag: "stopped-twice",
        executionTimeoutInterval: .seconds(10),
        stopTimeoutInterval: .seconds(1),
        execute: { _ in started.fulfill() },
        stopWhenExecuting: { stopped in
            capturedStopped = stopped
        }
    )

    task.perform(by: executeQueue, timeoutQueue: .global())
    wait(for: [started], timeout: 1.0)

    let request = task.makeStopRequest(timeoutQueue: .global()) {
        lock.lock()
        finishCount += 1
        lock.unlock()
        stopFinished.fulfill()
    }
    XCTAssertNotNil(request)
    request?()

    waitUntil { capturedStopped != nil }
    capturedStopped?()
    capturedStopped?()
    wait(for: [stopFinished], timeout: 1.0)

    Thread.sleep(forTimeInterval: 0.1)
    lock.lock()
    let finalFinishCount = finishCount
    lock.unlock()
    XCTAssertEqual(finalFinishCount, 1)
}

func test_makeStopRequest_timeoutThenStopped_finishesOnlyOnce() {
    let started = expectation(description: "started")
    let stopFinished = expectation(description: "stop finished")
    let executeQueue = DispatchQueue(label: "OnceTimeoutTaskTests.timeoutThenStopped")
    let lock = NSLock()
    var finishCount = 0
    var capturedStopped: OnceTimeoutTask<Int, TestError>.Stopped?

    let task = OnceTimeoutTask<Int, TestError>(
        flag: "timeout-then-stopped",
        executionTimeoutInterval: .seconds(10),
        stopTimeoutInterval: .milliseconds(80),
        execute: { _ in started.fulfill() },
        stopWhenExecuting: { stopped in
            capturedStopped = stopped
        }
    )

    task.perform(by: executeQueue, timeoutQueue: .global())
    wait(for: [started], timeout: 1.0)

    let request = task.makeStopRequest(timeoutQueue: .global()) {
        lock.lock()
        finishCount += 1
        lock.unlock()
        stopFinished.fulfill()
    }
    XCTAssertNotNil(request)
    request?()

    wait(for: [stopFinished], timeout: 1.0)
    capturedStopped?()
    Thread.sleep(forTimeInterval: 0.1)

    lock.lock()
    let finalFinishCount = finishCount
    lock.unlock()
    XCTAssertEqual(finalFinishCount, 1)
}

func test_makeStopRequest_stoppedThenTimeout_finishesOnlyOnce() {
    let started = expectation(description: "started")
    let stopFinished = expectation(description: "stop finished")
    let executeQueue = DispatchQueue(label: "OnceTimeoutTaskTests.stoppedThenTimeout")
    let lock = NSLock()
    var finishCount = 0
    var capturedStopped: OnceTimeoutTask<Int, TestError>.Stopped?

    let task = OnceTimeoutTask<Int, TestError>(
        flag: "stopped-then-timeout",
        executionTimeoutInterval: .seconds(10),
        stopTimeoutInterval: .milliseconds(80),
        execute: { _ in started.fulfill() },
        stopWhenExecuting: { stopped in
            capturedStopped = stopped
        }
    )

    task.perform(by: executeQueue, timeoutQueue: .global())
    wait(for: [started], timeout: 1.0)

    let request = task.makeStopRequest(timeoutQueue: .global()) {
        lock.lock()
        finishCount += 1
        lock.unlock()
        stopFinished.fulfill()
    }
    XCTAssertNotNil(request)
    request?()

    waitUntil { capturedStopped != nil }
    capturedStopped?()
    wait(for: [stopFinished], timeout: 1.0)
    Thread.sleep(forTimeInterval: 0.1)

    lock.lock()
    let finalFinishCount = finishCount
    lock.unlock()
    XCTAssertEqual(finalFinishCount, 1)
}

func test_makeRestartStopRequest_staleCompletionDoesNotFinishInterruptedRun() {
    let started = expectation(description: "started")
    let restartStopFinished = expectation(description: "restart stop finished")
    let executeQueue = DispatchQueue(label: "OnceTimeoutTaskTests.restartStaleCompletion")
    var capturedCompletion: OnceTimeoutTask<Int, TestError>.Completed?
    var capturedStopped: OnceTimeoutTask<Int, TestError>.Stopped?

    let task = OnceTimeoutTask<Int, TestError>(
        flag: "restart-stale-completion",
        executionTimeoutInterval: .seconds(10),
        stopTimeoutInterval: .seconds(1),
        execute: { completed in
            capturedCompletion = completed
            started.fulfill()
        },
        stopWhenExecuting: { stopped in
            capturedStopped = stopped
        }
    )

    task.perform(by: executeQueue, timeoutQueue: .global())
    wait(for: [started], timeout: 1.0)

    let request = task.makeRestartStopRequest(timeoutQueue: .global()) {
        restartStopFinished.fulfill()
    }
    XCTAssertNotNil(request)
    request?()

    guard case .waitingRestart(stopped: false) = task.state else {
        XCTFail("Expected waitingRestart(false), got \(task.state)")
        return
    }

    capturedCompletion?(.success(123))
    guard case .waitingRestart(stopped: false) = task.state else {
        XCTFail("Expected stale completion to be ignored, got \(task.state)")
        return
    }

    capturedStopped?()
    wait(for: [restartStopFinished], timeout: 1.0)
    guard case .waitingRestart(stopped: true) = task.state else {
        XCTFail("Expected waitingRestart(true), got \(task.state)")
        return
    }
}

func test_makeRestartStopRequest_staleExecutionTimeoutDoesNotFinishInterruptedRun() {
    let started = expectation(description: "started")
    let restartStopFinished = expectation(description: "restart stop finished")
    let executeQueue = DispatchQueue(label: "OnceTimeoutTaskTests.restartStaleTimeout")
    var capturedStopped: OnceTimeoutTask<Int, TestError>.Stopped?

    let task = OnceTimeoutTask<Int, TestError>(
        flag: "restart-stale-timeout",
        executionTimeoutInterval: .milliseconds(80),
        stopTimeoutInterval: .seconds(1),
        execute: { _ in started.fulfill() },
        stopWhenExecuting: { stopped in
            capturedStopped = stopped
        }
    )

    task.perform(by: executeQueue, timeoutQueue: .global())
    wait(for: [started], timeout: 1.0)

    let request = task.makeRestartStopRequest(timeoutQueue: .global()) {
        restartStopFinished.fulfill()
    }
    XCTAssertNotNil(request)
    request?()

    guard case .waitingRestart(stopped: false) = task.state else {
        XCTFail("Expected waitingRestart(false), got \(task.state)")
        return
    }

    Thread.sleep(forTimeInterval: 0.12)
    guard case .waitingRestart(stopped: false) = task.state else {
        XCTFail("Expected stale timeout to be ignored, got \(task.state)")
        return
    }

    capturedStopped?()
    wait(for: [restartStopFinished], timeout: 1.0)
    guard case .waitingRestart(stopped: true) = task.state else {
        XCTFail("Expected waitingRestart(true), got \(task.state)")
        return
    }
}
```

- [ ] **Step 2: Run focused task tests and confirm they pass**

Run:

```bash
rtk xcodebuild test -project Project/RYKit.xcodeproj -scheme RYKitTests -destination 'platform=macOS' -only-testing:RYKitTests/OnceTimeoutTaskTests BUILD_LIBRARY_FOR_DISTRIBUTION=NO
```

Expected: PASS. These tests exercise existing generation and stop-timeout protections.

- [ ] **Step 3: Commit Task 2**

```bash
rtk git add Project/RYKitTests/TimeoutTaskTests.swift
rtk git commit -m "Add timeout task race coverage" -m "Cover duplicate stop calls, stop timeout races, and stale completion/timeout signals during restart flows." -m "Tested: xcodebuild OnceTimeoutTaskTests BUILD_LIBRARY_FOR_DISTRIBUTION=NO"
```

---

### Task 3: Add Queue Ownership Visibility And `allTasks` Coverage

**Files:**
- Modify: `Project/RYKitTests/TimeoutTaskTests.swift`
- Test: `Project/RYKitTests/TimeoutTaskTests.swift`

- [ ] **Step 1: Add ownership and snapshot tests to `OnceTimeoutTaskQueueTests`**

Append these tests inside `final class OnceTimeoutTaskQueueTests: XCTestCase`:

```swift
func test_allTasks_whenPaused_returnsWaitingTasksInPriorityThenFIFOOrder() {
    let queue = OnceTimeoutTaskQueue<Int, TestError>(executeQueue: .global())
    queue.pause()

    queue.addTask(makeTask(flag: "low", value: 1), priority: 0)
    queue.addTask(makeTask(flag: "high-a", value: 2), priority: 10)
    queue.addTask(makeTask(flag: "high-b", value: 3), priority: 10)
    queue.addTask(makeTask(flag: "mid", value: 4), priority: 5)

    XCTAssertEqual(queue.allTasks.map(\.flag), ["high-a", "high-b", "mid", "low"])
}

func test_allTasks_duringDiscardPreemption_includesWaitingAndStoppingExactlyOnce() {
    let queue = OnceTimeoutTaskQueue<Int, TestError>(executeQueue: .global())
    let currentStarted = expectation(description: "current started")
    var capturedStopped: (() -> Void)?

    let current = OnceTimeoutTask<Int, TestError>(
        flag: "current",
        executionTimeoutInterval: .seconds(10),
        stopTimeoutInterval: .seconds(1),
        execute: { _ in currentStarted.fulfill() },
        stopWhenExecuting: { stopped in
            capturedStopped = stopped
        }
    )
    let high = makeTask(flag: "high", value: 2)

    queue.addTask(current, priority: 0)
    wait(for: [currentStarted], timeout: 1.0)
    queue.addTask(high, priority: 10, preemptionStrategy: .stopCurrentAndDiscard)

    waitUntil { capturedStopped != nil }
    let flags = queue.allTasks.map(\.flag)
    XCTAssertEqual(flags, ["high", "current"])
    XCTAssertEqual(Set(flags).count, 2)
}

func test_waitingTaskDirectStop_removesStoppedTaskFromAllTasks() {
    let queue = OnceTimeoutTaskQueue<Int, TestError>(executeQueue: .global())
    let recorder = FinishEventRecorder(queue: queue)
    queue.pause()

    let first = makeTask(flag: "first", value: 1)
    let second = makeTask(flag: "second", value: 2)
    queue.addTask(first, priority: 1)
    queue.addTask(second, priority: 0)

    first.stop()

    waitUntil { recorder.flags == ["first"] }
    XCTAssertEqual(queue.allTasks.map(\.flag), ["second"])
}

func test_stopAllWhere_noMatch_keepsAllTasksAndEmitsNoEvents() {
    let queue = OnceTimeoutTaskQueue<Int, TestError>(executeQueue: .global())
    let recorder = FinishEventRecorder(queue: queue)
    queue.pause()

    queue.addTask(makeTask(flag: "one", value: 1), priority: 10)
    queue.addTask(makeTask(flag: "two", value: 2), priority: 0)

    let before = queue.allTasks.map(\.flag)
    queue.stopAll { $0.flag == "missing" }

    XCTAssertEqual(queue.allTasks.map(\.flag), before)
    XCTAssertTrue(recorder.flags.isEmpty)
}

func test_stopAllWhere_partialWaitingRemoval_preservesRemainingPriorityOrder() {
    let queue = OnceTimeoutTaskQueue<Int, TestError>(executeQueue: .global())
    let recorder = FinishEventRecorder(queue: queue)
    queue.pause()

    queue.addTask(makeTask(flag: "low", value: 1), priority: 0)
    queue.addTask(makeTask(flag: "remove", value: 2), priority: 7)
    queue.addTask(makeTask(flag: "mid", value: 3), priority: 3)
    queue.addTask(makeTask(flag: "high", value: 4), priority: 10)

    queue.stopAll { $0.flag == "remove" }

    waitUntil { recorder.flags == ["remove"] }
    XCTAssertEqual(queue.allTasks.map(\.flag), ["high", "mid", "low"])
}

func test_allTasks_afterRequeueStopCompletion_reinsertsTaskOnce() {
    let queue = OnceTimeoutTaskQueue<Int, TestError>(executeQueue: .global())
    let currentStarted = expectation(description: "current started")
    let highStarted = expectation(description: "high started")
    let allowHighToFinish = DispatchSemaphore(value: 0)
    let lock = NSLock()
    var currentRunCount = 0
    var capturedStopped: (() -> Void)?

    let current = OnceTimeoutTask<Int, TestError>(
        flag: "current",
        executionTimeoutInterval: .seconds(10),
        stopTimeoutInterval: .seconds(1),
        execute: { completed in
            lock.lock()
            currentRunCount += 1
            let run = currentRunCount
            lock.unlock()

            if run == 1 {
                currentStarted.fulfill()
            } else {
                completed(.success(1))
            }
        },
        stopWhenExecuting: { stopped in
            capturedStopped = stopped
        }
    )
    let low = makeTask(flag: "low", value: 2)
    let high = OnceTimeoutTask<Int, TestError>(
        flag: "high",
        executionTimeoutInterval: .seconds(10),
        stopTimeoutInterval: .milliseconds(100),
        execute: { completed in
            highStarted.fulfill()
            allowHighToFinish.wait()
            completed(.success(3))
        },
        stopWhenExecuting: { stopped in stopped() }
    )

    queue.addTask(current, priority: 5)
    wait(for: [currentStarted], timeout: 1.0)
    queue.addTask(low, priority: 1)
    queue.addTask(high, priority: 10, preemptionStrategy: .stopCurrentAndRequeue)

    waitUntil { capturedStopped != nil }
    capturedStopped?()
    wait(for: [highStarted], timeout: 1.0)

    let flagsWhileHighRuns = queue.allTasks.map(\.flag)
    XCTAssertEqual(flagsWhileHighRuns, ["current", "low", "high"])
    XCTAssertEqual(Set(flagsWhileHighRuns).count, 3)

    allowHighToFinish.signal()
}
```

- [ ] **Step 2: Run focused queue tests and confirm they pass**

Run:

```bash
rtk xcodebuild test -project Project/RYKit.xcodeproj -scheme RYKitTests -destination 'platform=macOS' -only-testing:RYKitTests/OnceTimeoutTaskQueueTests BUILD_LIBRARY_FOR_DISTRIBUTION=NO
```

Expected: PASS if `allTasks` is already present in the working branch, which it is in the current workspace state.

- [ ] **Step 3: Commit Task 3**

```bash
rtk git add Project/RYKitTests/TimeoutTaskTests.swift
rtk git commit -m "Add timeout queue ownership coverage" -m "Cover allTasks snapshots, no-match stopAll semantics, and requeue ownership visibility." -m "Tested: xcodebuild OnceTimeoutTaskQueueTests BUILD_LIBRARY_FOR_DISTRIBUTION=NO"
```

---

### Task 4: Add Queue Scheduling Edge Tests And Fix The Gaps They Expose

**Files:**
- Modify: `Project/RYKitTests/TimeoutTaskTests.swift`
- Modify: `Classes/Core/TimeoutTask/OnceTimeoutTaskQueue.swift`
- Test: `Project/RYKitTests/TimeoutTaskTests.swift`

- [ ] **Step 1: Add scheduling-edge tests that should fail on current queue code**

Append these tests inside `OnceTimeoutTaskQueueTests`:

```swift
func test_addTask_waitingRestartStoppedTrue_doesNotDuplicateSameInstance() {
    let queue = OnceTimeoutTaskQueue<Int, TestError>(executeQueue: .global())
    queue.pause()

    let task = makeTask(flag: "restart-ready", value: 1)
    task.setWaitingRestartForTest(stopped: true)

    queue.addTask(task, priority: 5)
    queue.addTask(task, priority: 5)

    XCTAssertEqual(queue.allTasks.map(\.flag), ["restart-ready"])
    XCTAssertTrue(queue.allTasks.first === task)
}

func test_addTask_higherPriorityWhilePaused_doesNotPreemptCurrent() {
    let queue = OnceTimeoutTaskQueue<Int, TestError>(executeQueue: .global())
    let currentStarted = expectation(description: "current started")
    let allowCurrentToFinish = DispatchSemaphore(value: 0)
    let recorder = FinishEventRecorder(queue: queue)
    let lock = NSLock()
    var stopCallCount = 0

    let current = OnceTimeoutTask<Int, TestError>(
        flag: "current",
        executionTimeoutInterval: .seconds(10),
        stopTimeoutInterval: .seconds(1),
        execute: { completed in
            currentStarted.fulfill()
            allowCurrentToFinish.wait()
            completed(.success(1))
        },
        stopWhenExecuting: { stopped in
            lock.lock()
            stopCallCount += 1
            lock.unlock()
            stopped()
        }
    )
    let high = makeTask(flag: "high", value: 2)

    queue.addTask(current, priority: 0)
    wait(for: [currentStarted], timeout: 1.0)
    queue.pause()
    queue.addTask(high, priority: 10, preemptionStrategy: .stopCurrentAndDiscard)

    Thread.sleep(forTimeInterval: 0.15)
    lock.lock()
    let finalStopCallCount = stopCallCount
    lock.unlock()
    XCTAssertEqual(finalStopCallCount, 0)
    XCTAssertEqual(queue.allTasks.map(\.flag), ["high", "current"])

    queue.resume()
    allowCurrentToFinish.signal()
    waitUntil { recorder.flags == ["current", "high"] }
}

func test_addTask_higherPriorityWhileStopping_doesNotTriggerSecondPreemption() {
    let queue = OnceTimeoutTaskQueue<Int, TestError>(executeQueue: .global())
    let currentStarted = expectation(description: "current started")
    let recorder = FinishEventRecorder(queue: queue)
    let lock = NSLock()
    var stopCallCount = 0
    var capturedStopped: (() -> Void)?

    let current = OnceTimeoutTask<Int, TestError>(
        flag: "current",
        executionTimeoutInterval: .seconds(10),
        stopTimeoutInterval: .seconds(1),
        execute: { _ in currentStarted.fulfill() },
        stopWhenExecuting: { stopped in
            lock.lock()
            stopCallCount += 1
            capturedStopped = stopped
            lock.unlock()
        }
    )
    let high = OnceTimeoutTask<Int, TestError>(
        flag: "high",
        executionTimeoutInterval: .seconds(10),
        stopTimeoutInterval: .milliseconds(100),
        execute: { completed in
            completed(.success(2))
        },
        stopWhenExecuting: { stopped in stopped() }
    )
    let higher = makeTask(flag: "higher", value: 3)

    queue.addTask(current, priority: 0)
    wait(for: [currentStarted], timeout: 1.0)
    queue.addTask(high, priority: 10, preemptionStrategy: .stopCurrentAndDiscard)
    waitUntil { capturedStopped != nil }
    queue.addTask(higher, priority: 20, preemptionStrategy: .stopCurrentAndDiscard)

    lock.lock()
    let finalStopCallCount = stopCallCount
    lock.unlock()
    XCTAssertEqual(finalStopCallCount, 1)
    XCTAssertEqual(queue.allTasks.map(\.flag), ["higher", "high", "current"])

    capturedStopped?()
    waitUntil { recorder.flags == ["current", "higher", "high"] }
}

func test_stopCurrentAndRequeue_restartsBeforeLowerPriorityWaitingTask() {
    let queue = OnceTimeoutTaskQueue<Int, TestError>(executeQueue: .global())
    let currentStarted = expectation(description: "current started")
    let allFinished = expectation(description: "all finished")
    allFinished.expectedFulfillmentCount = 3
    let lock = NSLock()
    var runCount = 0
    var executionOrder: [String] = []
    var capturedStopped: (() -> Void)?

    queue.taskDidFinish
        .sink { _ in allFinished.fulfill() }
        .store(in: &cancellables)

    let current = OnceTimeoutTask<Int, TestError>(
        flag: "current",
        executionTimeoutInterval: .seconds(10),
        stopTimeoutInterval: .seconds(1),
        execute: { completed in
            lock.lock()
            runCount += 1
            let currentRun = runCount
            executionOrder.append("current-\(currentRun)")
            lock.unlock()

            if currentRun == 1 {
                currentStarted.fulfill()
            } else {
                completed(.success(1))
            }
        },
        stopWhenExecuting: { stopped in
            capturedStopped = stopped
        }
    )
    let low = makeTask(flag: "low", value: 2, onExecute: {
        lock.lock()
        executionOrder.append("low")
        lock.unlock()
    })
    let high = makeTask(flag: "high", value: 3, onExecute: {
        lock.lock()
        executionOrder.append("high")
        lock.unlock()
    })

    queue.addTask(current, priority: 5)
    wait(for: [currentStarted], timeout: 1.0)
    queue.addTask(low, priority: 1)
    queue.addTask(high, priority: 10, preemptionStrategy: .stopCurrentAndRequeue)

    waitUntil { capturedStopped != nil }
    capturedStopped?()
    wait(for: [allFinished], timeout: 2.0)

    XCTAssertEqual(executionOrder, ["current-1", "high", "current-2", "low"])
}
```

- [ ] **Step 2: Run the queue tests and confirm the current implementation fails**

Run:

```bash
rtk xcodebuild test -project Project/RYKit.xcodeproj -scheme RYKitTests -destination 'platform=macOS' -only-testing:RYKitTests/OnceTimeoutTaskQueueTests BUILD_LIBRARY_FOR_DISTRIBUTION=NO
```

Expected: FAIL. The current queue code allows duplicate ownership for the same task instance and still considers stop-based preemption even while paused.

- [ ] **Step 3: Make the minimal queue fixes**

Update `Classes/Core/TimeoutTask/OnceTimeoutTaskQueue.swift` as follows:

```swift
public func addTask(
    _ task: Task,
    priority: Int = 0,
    preemptionStrategy: PreemptionStrategy? = nil
) {
    guard task.state.canEnqueue else {
        return
    }

    let strategy = preemptionStrategy ?? defaultPreemptionStrategy
    let stopRequest: (() -> Void)?

    lock.lock()
    guard !containsTaskLocked(task) else {
        lock.unlock()
        return
    }

    task.onDone = { [weak self, weak task] doneType in
        guard let task else { return }
        self?.handleTaskDone(task, doneType: doneType)
    }

    let item = makeQueuedTaskLocked(task: task, priority: priority)
    if !paused, let current, item.priority > current.priority {
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
    lock.unlock()

    stopRequest?()
    start(takeNextAfterCleaning())
}

private func containsTaskLocked(_ task: Task) -> Bool {
    waiting.contains { $0.task === task }
        || current?.task === task
        || stopping?.task === task
}
```

Do not change queue ordering, event emission, or stop-disposition semantics beyond these two fixes.

- [ ] **Step 4: Re-run focused queue tests and confirm they pass**

Run:

```bash
rtk xcodebuild test -project Project/RYKit.xcodeproj -scheme RYKitTests -destination 'platform=macOS' -only-testing:RYKitTests/OnceTimeoutTaskQueueTests BUILD_LIBRARY_FOR_DISTRIBUTION=NO
```

Expected: PASS.

- [ ] **Step 5: Commit Task 4**

```bash
rtk git add Classes/Core/TimeoutTask/OnceTimeoutTaskQueue.swift Project/RYKitTests/TimeoutTaskTests.swift
rtk git commit -m "Fix queue edge cases covered by new tests" -m "Prevent duplicate queue ownership of the same task and suppress stop-based preemption while paused." -m "Tested: xcodebuild OnceTimeoutTaskQueueTests BUILD_LIBRARY_FOR_DISTRIBUTION=NO"
```

---

### Task 5: Add A Non-Stoppable Test Seam And Cover The Existing Fallback Branch

**Files:**
- Modify: `Classes/Core/TimeoutTask/OnceTimeoutTask.swift`
- Modify: `Project/RYKitTests/TimeoutTaskTests.swift`
- Test: `Project/RYKitTests/TimeoutTaskTests.swift`

- [ ] **Step 1: Add tests for the non-stoppable-current fallback branch**

First add this helper inside `OnceTimeoutTaskQueueTests`:

```swift
private func makeNonStoppableTask(
    flag: String,
    value: Int,
    start: XCTestExpectation? = nil,
    gate: DispatchSemaphore? = nil,
    onExecute: (() -> Void)? = nil,
    onStop: (() -> Void)? = nil
) -> OnceTimeoutTask<Int, TestError> {
    OnceTimeoutTask<Int, TestError>(
        flag: flag,
        executionTimeoutInterval: .seconds(10),
        stopTimeoutInterval: .seconds(1),
        isStoppable: false,
        execute: { completed in
            onExecute?()
            start?.fulfill()
            gate?.wait()
            completed(.success(value))
        },
        stopWhenExecuting: { stopped in
            onStop?()
            stopped()
        }
    )
}
```

Then add these tests:

```swift
func test_stopCurrentAndDiscard_withNonStoppableCurrent_waitsForCompletion() {
    let queue = OnceTimeoutTaskQueue<Int, TestError>(executeQueue: .global())
    let currentStarted = expectation(description: "current started")
    let allFinished = expectation(description: "all finished")
    allFinished.expectedFulfillmentCount = 2
    let allowCurrentToFinish = DispatchSemaphore(value: 0)
    let counterLock = NSLock()
    var stopCallCount = 0
    var executionOrder: [String] = []
    let orderLock = NSLock()

    queue.taskDidFinish
        .sink { _ in allFinished.fulfill() }
        .store(in: &cancellables)

    let current = makeNonStoppableTask(
        flag: "current",
        value: 1,
        start: currentStarted,
        gate: allowCurrentToFinish,
        onExecute: {
            orderLock.lock()
            executionOrder.append("current")
            orderLock.unlock()
        },
        onStop: {
            counterLock.lock()
            stopCallCount += 1
            counterLock.unlock()
        }
    )
    let high = makeTask(flag: "high", value: 2, onExecute: {
        orderLock.lock()
        executionOrder.append("high")
        orderLock.unlock()
    })
    queue.addTask(current, priority: 0)
    wait(for: [currentStarted], timeout: 1.0)
    queue.addTask(high, priority: 10, preemptionStrategy: .stopCurrentAndDiscard)

    Thread.sleep(forTimeInterval: 0.15)
    counterLock.lock()
    let finalStopCallCount = stopCallCount
    counterLock.unlock()
    XCTAssertEqual(finalStopCallCount, 0)

    allowCurrentToFinish.signal()
    wait(for: [allFinished], timeout: 2.0)
    XCTAssertEqual(executionOrder, ["current", "high"])
}

func test_stopCurrentAndRequeue_withNonStoppableCurrent_waitsForCompletion() {
    let queue = OnceTimeoutTaskQueue<Int, TestError>(executeQueue: .global())
    let currentStarted = expectation(description: "current started")
    let allFinished = expectation(description: "all finished")
    allFinished.expectedFulfillmentCount = 2
    let allowCurrentToFinish = DispatchSemaphore(value: 0)
    let counterLock = NSLock()
    var stopCallCount = 0
    var executionOrder: [String] = []
    let orderLock = NSLock()

    queue.taskDidFinish
        .sink { _ in allFinished.fulfill() }
        .store(in: &cancellables)

    let current = makeNonStoppableTask(
        flag: "current",
        value: 1,
        start: currentStarted,
        gate: allowCurrentToFinish,
        onExecute: {
            orderLock.lock()
            executionOrder.append("current")
            orderLock.unlock()
        },
        onStop: {
            counterLock.lock()
            stopCallCount += 1
            counterLock.unlock()
        }
    )
    let high = makeTask(flag: "high", value: 2, onExecute: {
        orderLock.lock()
        executionOrder.append("high")
        orderLock.unlock()
    })
    queue.addTask(current, priority: 0)
    wait(for: [currentStarted], timeout: 1.0)
    queue.addTask(high, priority: 10, preemptionStrategy: .stopCurrentAndRequeue)

    Thread.sleep(forTimeInterval: 0.15)
    counterLock.lock()
    let finalStopCallCount = stopCallCount
    counterLock.unlock()
    XCTAssertEqual(finalStopCallCount, 0)

    allowCurrentToFinish.signal()
    wait(for: [allFinished], timeout: 2.0)
    XCTAssertEqual(executionOrder, ["current", "high"])
}
```

- [ ] **Step 2: Run focused queue tests and confirm they fail to compile or fail to construct a non-stoppable task**

Run:

```bash
rtk xcodebuild test -project Project/RYKit.xcodeproj -scheme RYKitTests -destination 'platform=macOS' -only-testing:RYKitTests/OnceTimeoutTaskQueueTests BUILD_LIBRARY_FOR_DISTRIBUTION=NO
```

Expected: FAIL because `OnceTimeoutTask` does not yet expose an internal way to construct `isStoppable == false`.

- [ ] **Step 3: Add the narrow internal `isStoppable` seam**

Update `Classes/Core/TimeoutTask/OnceTimeoutTask.swift` so the public API stays unchanged while tests gain an internal initializer:

```swift
private let supportsStopWhenExecuting: Bool

var isStoppable: Bool {
    supportsStopWhenExecuting
}

public init(
    flag: String,
    executionTimeoutInterval: DispatchTimeInterval?,
    stopTimeoutInterval: DispatchTimeInterval?,
    execute: @escaping (@escaping Completed) -> Void,
    stopWhenExecuting: @escaping StopWhenExecuting = { stopped in stopped() }
) {
    self.init(
        flag: flag,
        executionTimeoutInterval: executionTimeoutInterval,
        stopTimeoutInterval: stopTimeoutInterval,
        isStoppable: true,
        execute: execute,
        stopWhenExecuting: stopWhenExecuting
    )
}

init(
    flag: String,
    executionTimeoutInterval: DispatchTimeInterval?,
    stopTimeoutInterval: DispatchTimeInterval?,
    isStoppable: Bool,
    execute: @escaping (@escaping Completed) -> Void,
    stopWhenExecuting: @escaping StopWhenExecuting = { stopped in stopped() }
) {
    self.flag = flag
    self.executionTimeoutInterval = executionTimeoutInterval
    self.stopTimeoutInterval = stopTimeoutInterval
    self.supportsStopWhenExecuting = isStoppable
    self.execute = execute
    self.stopAction = stopWhenExecuting
}
```

Do not change the async convenience initializer; it should continue to use the public initializer and therefore keep `isStoppable == true` by default.

- [ ] **Step 4: Re-run focused queue tests and confirm they pass**

Run:

```bash
rtk xcodebuild test -project Project/RYKit.xcodeproj -scheme RYKitTests -destination 'platform=macOS' -only-testing:RYKitTests/OnceTimeoutTaskQueueTests BUILD_LIBRARY_FOR_DISTRIBUTION=NO
```

Expected: PASS.

- [ ] **Step 5: Run the full verification suite**

Run:

```bash
rtk xcodebuild test -project Project/RYKit.xcodeproj -scheme RYKitTests -destination 'platform=macOS' -only-testing:RYKitTests/OnceTimeoutTaskTests BUILD_LIBRARY_FOR_DISTRIBUTION=NO
rtk xcodebuild test -project Project/RYKit.xcodeproj -scheme RYKitTests -destination 'platform=macOS' -only-testing:RYKitTests/OnceTimeoutTaskQueueTests BUILD_LIBRARY_FOR_DISTRIBUTION=NO
rtk xcodebuild test -project Project/RYKit.xcodeproj -scheme RYKitTests -destination 'platform=macOS' BUILD_LIBRARY_FOR_DISTRIBUTION=NO
rtk swift build
rtk proxy git diff --check
```

Expected: all commands pass.

- [ ] **Step 6: Commit Task 5**

```bash
rtk git add Classes/Core/TimeoutTask/OnceTimeoutTask.swift Project/RYKitTests/TimeoutTaskTests.swift
rtk git commit -m "Cover non-stoppable timeout queue fallback" -m "Add an internal test seam for non-stoppable tasks and verify stop-based strategies degrade to waitCurrentCompletion." -m "Tested: xcodebuild OnceTimeoutTaskTests/OnceTimeoutTaskQueueTests/full suite BUILD_LIBRARY_FOR_DISTRIBUTION=NO; swift build; git diff --check"
```
