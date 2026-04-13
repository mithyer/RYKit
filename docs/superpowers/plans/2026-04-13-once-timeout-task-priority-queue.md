# OnceTimeoutTask Priority Queue Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Implement stop-aware, priority-ordered `OnceTimeoutTaskQueue` behavior with task flags, async task initialization, and queue finish events.

**Architecture:** `OnceTimeoutTask` owns the task state machine and exposes internal queue hooks for completion, stop coordination, cancellation, and requeue reset. `OnceTimeoutTaskQueue` stops inheriting from `Queue`, stores private priority metadata, executes one current task, waits for `stopped()` or task stop timeout during preemption, and emits Combine finish events only when a task leaves queue ownership.

**Tech Stack:** Swift, Foundation, Combine `PassthroughSubject`, XCTest, existing `UnfairLock`.

---

## File Structure

- Modify `Classes/Core/TimeoutTask/OnceTimeoutTask.swift`
  - Owns `flag`, `executionTimeoutInterval`, `stopTimeoutInterval`, callback and async initializers, public `cancel()`/`stop()`, internal queue cancellation, internal stop request, and internal requeue reset.
- Modify `Classes/Core/TimeoutTask/OnceTimeoutTaskQueue.swift`
  - Owns `PreemptionStrategy`, `TaskFinishEvent`, `taskDidFinish`, priority insertion, current task tracking, stop coordination, pause/resume, and cancel-all behavior.
- Modify `Project/RYKitTests/TimeoutTaskTests.swift`
  - Replaces old `done`-callback tests with state inspection and queue finish-event tests.
- Modify `README.md`
  - Updates English and Chinese `TimeoutTask` examples to the new required stop-aware API and priority queue usage.

## Verification Commands

Use these commands after implementation tasks:

```bash
rtk xcodebuild test -project Project/RYKit.xcodeproj -scheme RYKitTests -destination 'platform=macOS' -only-testing:RYKitTests/OnceTimeoutTaskTests
rtk xcodebuild test -project Project/RYKit.xcodeproj -scheme RYKitTests -destination 'platform=macOS' -only-testing:RYKitTests/OnceTimeoutTaskQueueTests
rtk xcodebuild test -project Project/RYKit.xcodeproj -scheme RYKitTests -destination 'platform=macOS'
rtk swift build
```

Expected final result: all commands pass.

---

### Task 1: Migrate OnceTimeoutTask API And State Machine

**Files:**
- Modify: `Project/RYKitTests/TimeoutTaskTests.swift`
- Modify: `Classes/Core/TimeoutTask/OnceTimeoutTask.swift`

- [ ] **Step 1: Replace the `OnceTimeoutTaskTests` class with state-based tests**

In `Project/RYKitTests/TimeoutTaskTests.swift`, replace the existing `OnceTimeoutTaskTests` class with:

```swift
final class OnceTimeoutTaskTests: XCTestCase {
    
    enum TestError: Error {
        case failed
    }
    
    private func assertCompletedSuccess(
        _ doneType: OnceTimeoutTask<Int, TestError>.DoneType?,
        equals expected: Int,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        guard case .completed(let result) = doneType else {
            XCTFail("Expected completed success, got \(String(describing: doneType))", file: file, line: line)
            return
        }
        XCTAssertEqual(try? result.get(), expected, file: file, line: line)
    }
    
    private func doneType(
        of task: OnceTimeoutTask<Int, TestError>
    ) -> OnceTimeoutTask<Int, TestError>.DoneType? {
        if case .done(let doneType) = task.state {
            return doneType
        }
        return nil
    }
    
    func test_init_storesFlagAndStateIsUnstart() {
        let task = OnceTimeoutTask<Int, TestError>(
            flag: "task-1",
            executionTimeoutInterval: .seconds(1),
            stopTimeoutInterval: .milliseconds(100),
            execute: { _ in },
            stop: { stopped in stopped() }
        )
        
        XCTAssertEqual(task.flag, "task-1")
        XCTAssertFalse(task.state.hasStarted)
        XCTAssertFalse(task.state.isDone)
    }
    
    func test_perform_stateBecomesExecuting() {
        let task = OnceTimeoutTask<Int, TestError>(
            flag: "task-1",
            executionTimeoutInterval: .seconds(10),
            stopTimeoutInterval: .milliseconds(100),
            execute: { _ in },
            stop: { stopped in stopped() }
        )
        
        task.perform(by: .global(), timeoutQueue: .global())
        
        Thread.sleep(forTimeInterval: 0.1)
        XCTAssertTrue(task.state.hasStarted)
        XCTAssertFalse(task.state.isDone)
    }
    
    func test_callbackExecute_successUpdatesState() {
        let executed = expectation(description: "executed")
        let task = OnceTimeoutTask<Int, TestError>(
            flag: "success",
            executionTimeoutInterval: .seconds(10),
            stopTimeoutInterval: .milliseconds(100),
            execute: { completed in
                completed(.success(42))
                executed.fulfill()
            },
            stop: { stopped in stopped() }
        )
        
        task.perform(by: .global(), timeoutQueue: .global())
        wait(for: [executed], timeout: 1.0)
        
        assertCompletedSuccess(doneType(of: task), equals: 42)
        XCTAssertTrue(task.state.isDone)
    }
    
    func test_callbackExecute_failureUpdatesState() {
        let executed = expectation(description: "executed")
        let task = OnceTimeoutTask<Int, TestError>(
            flag: "failure",
            executionTimeoutInterval: .seconds(10),
            stopTimeoutInterval: .milliseconds(100),
            execute: { completed in
                completed(.failure(.failed))
                executed.fulfill()
            },
            stop: { stopped in stopped() }
        )
        
        task.perform(by: .global(), timeoutQueue: .global())
        wait(for: [executed], timeout: 1.0)
        
        guard case .completed(let result) = doneType(of: task) else {
            XCTFail("Expected completed failure")
            return
        }
        XCTAssertThrowsError(try result.get())
    }
    
    func test_executionTimeout_updatesState() {
        let task = OnceTimeoutTask<Int, TestError>(
            flag: "timeout",
            executionTimeoutInterval: .milliseconds(80),
            stopTimeoutInterval: .milliseconds(100),
            execute: { _ in },
            stop: { stopped in stopped() }
        )
        
        task.perform(by: .global(), timeoutQueue: .global())
        Thread.sleep(forTimeInterval: 0.2)
        
        guard case .executionTimeout = doneType(of: task) else {
            XCTFail("Expected executionTimeout, got \(String(describing: doneType(of: task)))")
            return
        }
    }
    
    func test_stop_immediatelyMarksStoppedAndCallsStopClosure() {
        let started = expectation(description: "started")
        let stopCalled = expectation(description: "stop called")
        var capturedComplete: ((Result<Int, TestError>) -> Void)?
        
        let task = OnceTimeoutTask<Int, TestError>(
            flag: "stop",
            executionTimeoutInterval: .seconds(10),
            stopTimeoutInterval: .milliseconds(100),
            execute: { completed in
                capturedComplete = completed
                started.fulfill()
            },
            stop: { stopped in
                stopCalled.fulfill()
                stopped()
            }
        )
        
        task.perform(by: .global(), timeoutQueue: .global())
        wait(for: [started], timeout: 1.0)
        task.stop()
        wait(for: [stopCalled], timeout: 1.0)
        capturedComplete?(.success(1))
        
        guard case .stop = doneType(of: task) else {
            XCTFail("Expected stop, got \(String(describing: doneType(of: task)))")
            return
        }
    }
    
    func test_cancel_whenExecutingUpdatesState() {
        let started = expectation(description: "started")
        let task = OnceTimeoutTask<Int, TestError>(
            flag: "cancel",
            executionTimeoutInterval: .seconds(10),
            stopTimeoutInterval: .milliseconds(100),
            execute: { _ in started.fulfill() },
            stop: { stopped in stopped() }
        )
        
        task.perform(by: .global(), timeoutQueue: .global())
        wait(for: [started], timeout: 1.0)
        task.cancel()
        
        guard case .cancel = doneType(of: task) else {
            XCTFail("Expected cancel, got \(String(describing: doneType(of: task)))")
            return
        }
    }
    
    func test_asyncExecute_successUpdatesState() async throws {
        let task = OnceTimeoutTask<Int, TestError>(
            flag: "async-success",
            executionTimeoutInterval: .seconds(10),
            stopTimeoutInterval: .milliseconds(100),
            execute: {
                .success(7)
            },
            stop: {}
        )
        
        task.perform(by: .global(), timeoutQueue: .global())
        try await Task.sleep(nanoseconds: 100_000_000)
        
        assertCompletedSuccess(doneType(of: task), equals: 7)
    }
    
    func test_asyncExecute_failureUpdatesState() async throws {
        let task = OnceTimeoutTask<Int, TestError>(
            flag: "async-failure",
            executionTimeoutInterval: .seconds(10),
            stopTimeoutInterval: .milliseconds(100),
            execute: {
                .failure(.failed)
            },
            stop: {}
        )
        
        task.perform(by: .global(), timeoutQueue: .global())
        try await Task.sleep(nanoseconds: 100_000_000)
        
        guard case .completed(let result) = doneType(of: task) else {
            XCTFail("Expected completed failure")
            return
        }
        XCTAssertThrowsError(try result.get())
    }
}
```

- [ ] **Step 2: Run task tests and verify the new API fails before implementation**

Run:

```bash
rtk xcodebuild test -project Project/RYKit.xcodeproj -scheme RYKitTests -destination 'platform=macOS' -only-testing:RYKitTests/OnceTimeoutTaskTests
```

Expected: FAIL with compiler errors for missing `flag`, `executionTimeoutInterval`, `stopTimeoutInterval`, `.executionTimeout`, and async initializer.

- [ ] **Step 3: Replace `OnceTimeoutTask.swift` with the new state machine**

Replace the contents of `Classes/Core/TimeoutTask/OnceTimeoutTask.swift` with:

```swift
//
//  OnceTimeoutTask.swift
//  RYKit
//
//  Created by mao rui on 2026/1/7.
//

import Foundation

public class OnceTimeoutTask<T, E: Error> {
    
    public enum State {
        case unstart, executing, done(DoneType)
        
        var isDone: Bool {
            if case .done = self { true } else { false }
        }
        
        var hasStarted: Bool {
            if case .unstart = self { false } else { true }
        }
    }
    
    public enum DoneType {
        case executionTimeout
        case cancel
        case stop
        case completed(Result<T, E>)
    }
    
    public typealias Completed = (Result<T, E>) -> Void
    public typealias Stopped = () -> Void
    public typealias Stop = (@escaping Stopped) -> Void
    
    public let flag: String
    let executionTimeoutInterval: DispatchTimeInterval
    let stopTimeoutInterval: DispatchTimeInterval
    
    private let execute: (@escaping Completed) -> Void
    private let stopAction: Stop
    private let lock = UnfairLock()
    private var currentState: State = .unstart
    private var executionTimeoutItem: DispatchWorkItem?
    private var stopTimeoutItem: DispatchWorkItem?
    private var stopFinished: (() -> Void)?
    
    var onDone: ((DoneType) -> Void)?
    
    public var state: State {
        lock.lock()
        defer { lock.unlock() }
        return currentState
    }
    
    public init(
        flag: String,
        executionTimeoutInterval: DispatchTimeInterval,
        stopTimeoutInterval: DispatchTimeInterval,
        execute: @escaping (@escaping Completed) -> Void,
        stop: @escaping Stop
    ) {
        self.flag = flag
        self.executionTimeoutInterval = executionTimeoutInterval
        self.stopTimeoutInterval = stopTimeoutInterval
        self.execute = execute
        self.stopAction = stop
    }
    
    public convenience init(
        flag: String,
        executionTimeoutInterval: DispatchTimeInterval,
        stopTimeoutInterval: DispatchTimeInterval,
        execute: @escaping () async -> Result<T, E>,
        stop: @escaping () async -> Void
    ) {
        self.init(
            flag: flag,
            executionTimeoutInterval: executionTimeoutInterval,
            stopTimeoutInterval: stopTimeoutInterval,
            execute: { completed in
                Task {
                    completed(await execute())
                }
            },
            stop: { stopped in
                Task {
                    await stop()
                    stopped()
                }
            }
        )
    }
    
    func perform(by executeQueue: DispatchQueue, timeoutQueue: DispatchQueue) {
        let timeoutItem = DispatchWorkItem { [weak self] in
            self?.finish(with: .executionTimeout, notify: true)
        }
        let completed: Completed = { [weak self] result in
            self?.finish(with: .completed(result), notify: true)
        }
        
        lock.lock()
        guard case .unstart = currentState else {
            lock.unlock()
            return
        }
        currentState = .executing
        executionTimeoutItem = timeoutItem
        let interval = executionTimeoutInterval
        let execute = self.execute
        lock.unlock()
        
        timeoutQueue.asyncAfter(deadline: .now() + interval, execute: timeoutItem)
        executeQueue.async {
            execute(completed)
        }
    }
    
    public func cancel() {
        finish(with: .cancel, notify: true)
    }
    
    public func stop() {
        guard let request = makeStopRequest(timeoutQueue: .global(qos: .userInitiated), onStopped: {}) else {
            return
        }
        request()
    }
    
    @discardableResult
    func cancelFromQueue() -> DoneType? {
        transitionToCancel(allowUnstarted: true, notify: false)
    }
    
    func makeStopRequest(timeoutQueue: DispatchQueue, onStopped: @escaping () -> Void) -> (() -> Void)? {
        let stopTimeoutItem = DispatchWorkItem { [weak self] in
            self?.finishStop()
        }
        let stopped: Stopped = { [weak self] in
            self?.finishStop()
        }
        
        lock.lock()
        guard case .executing = currentState else {
            lock.unlock()
            return nil
        }
        currentState = .done(.stop)
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
    
    @discardableResult
    func resetForRequeue() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard case .done(.stop) = currentState else {
            return false
        }
        stopTimeoutItem?.cancel()
        stopTimeoutItem = nil
        stopFinished = nil
        executionTimeoutItem = nil
        currentState = .unstart
        return true
    }
    
    private func finish(with doneType: DoneType, notify: Bool) {
        let doneHandler: ((DoneType) -> Void)?
        
        lock.lock()
        guard case .executing = currentState else {
            lock.unlock()
            return
        }
        currentState = .done(doneType)
        executionTimeoutItem?.cancel()
        executionTimeoutItem = nil
        doneHandler = notify ? onDone : nil
        lock.unlock()
        
        doneHandler?(doneType)
    }
    
    private func transitionToCancel(allowUnstarted: Bool, notify: Bool) -> DoneType? {
        let doneHandler: ((DoneType) -> Void)?
        
        lock.lock()
        switch currentState {
        case .executing:
            break
        case .unstart where allowUnstarted:
            break
        default:
            lock.unlock()
            return nil
        }
        currentState = .done(.cancel)
        executionTimeoutItem?.cancel()
        executionTimeoutItem = nil
        doneHandler = notify ? onDone : nil
        lock.unlock()
        
        doneHandler?(.cancel)
        return .cancel
    }
    
    private func finishStop() {
        let handler: (() -> Void)?
        
        lock.lock()
        guard let stopFinished else {
            lock.unlock()
            return
        }
        handler = stopFinished
        self.stopFinished = nil
        stopTimeoutItem?.cancel()
        stopTimeoutItem = nil
        lock.unlock()
        
        handler?()
    }
}
```

- [ ] **Step 4: Build source and defer focused test pass until queue tests are migrated**

Run:

```bash
rtk swift build
```

Expected: PASS for source compilation. Do not require `OnceTimeoutTaskTests` to pass yet because the same test target still contains old queue tests that call the removed initializer. Task 2 migrates the queue tests, then the focused test commands become meaningful.

- [ ] **Step 5: Commit Task 1**

```bash
rtk git add Classes/Core/TimeoutTask/OnceTimeoutTask.swift Project/RYKitTests/TimeoutTaskTests.swift
rtk git commit -m "Migrate timeout task state API" -m "The task needs explicit identity, execution timeout naming, required stop coordination, and async construction before the queue can implement priority preemption." -m "Constraint: OnceTimeoutTask no longer exposes init done callbacks" -m "Confidence: high" -m "Scope-risk: moderate" -m "Tested: swift build"
```

---

### Task 2: Add Queue Finish Events And Priority Ordering Without Preemption

**Files:**
- Modify: `Project/RYKitTests/TimeoutTaskTests.swift`
- Modify: `Classes/Core/TimeoutTask/OnceTimeoutTaskQueue.swift`

- [ ] **Step 1: Add Combine import and queue test helpers**

At the top of `Project/RYKitTests/TimeoutTaskTests.swift`, add:

```swift
import Combine
```

Inside `OnceTimeoutTaskQueueTests`, add:

```swift
private var cancellables: Set<AnyCancellable> = []

override func tearDown() {
    cancellables.removeAll()
    super.tearDown()
}

private func makeTask(
    flag: String,
    value: Int,
    executionDelay: TimeInterval = 0,
    executionTimeoutInterval: DispatchTimeInterval = .seconds(10),
    stopTimeoutInterval: DispatchTimeInterval = .milliseconds(100),
    onExecute: (() -> Void)? = nil
) -> OnceTimeoutTask<Int, TestError> {
    OnceTimeoutTask<Int, TestError>(
        flag: flag,
        executionTimeoutInterval: executionTimeoutInterval,
        stopTimeoutInterval: stopTimeoutInterval,
        execute: { completed in
            onExecute?()
            if executionDelay > 0 {
                Thread.sleep(forTimeInterval: executionDelay)
            }
            completed(.success(value))
        },
        stop: { stopped in
            stopped()
        }
    )
}

private func doneType(
    of task: OnceTimeoutTask<Int, TestError>
) -> OnceTimeoutTask<Int, TestError>.DoneType? {
    if case .done(let doneType) = task.state {
        return doneType
    }
    return nil
}
```

- [ ] **Step 2: Replace existing queue tests with finish-event and priority baseline tests**

Replace the existing methods in `OnceTimeoutTaskQueueTests` with:

```swift
func test_addTask_executesImmediatelyAndEmitsFinishEvent() {
    let queue = OnceTimeoutTaskQueue<Int, TestError>(executeQueue: .global())
    let finished = expectation(description: "task finished")
    var events: [OnceTimeoutTaskQueue<Int, TestError>.TaskFinishEvent] = []
    
    queue.taskDidFinish
        .sink { event in
            events.append(event)
            finished.fulfill()
        }
        .store(in: &cancellables)
    
    let task = makeTask(flag: "first", value: 1)
    
    queue.addTask(task)
    wait(for: [finished], timeout: 1.0)
    
    XCTAssertEqual(events.map(\.flag), ["first"])
    XCTAssertTrue(events.first?.task === task)
    guard case .completed(let result) = events.first?.doneType else {
        XCTFail("Expected completed event")
        return
    }
    XCTAssertEqual(try? result.get(), 1)
}

func test_priorityOrdering_runsHigherPriorityFirstWhenPaused() {
    let queue = OnceTimeoutTaskQueue<Int, TestError>(executeQueue: .global())
    queue.pause()
    
    let allFinished = expectation(description: "all finished")
    allFinished.expectedFulfillmentCount = 3
    var executionOrder: [String] = []
    let lock = NSLock()
    
    queue.taskDidFinish
        .sink { _ in allFinished.fulfill() }
        .store(in: &cancellables)
    
    queue.addTask(makeTask(flag: "low", value: 1, onExecute: {
        lock.lock()
        executionOrder.append("low")
        lock.unlock()
    }), priority: 0)
    queue.addTask(makeTask(flag: "high", value: 2, onExecute: {
        lock.lock()
        executionOrder.append("high")
        lock.unlock()
    }), priority: 10)
    queue.addTask(makeTask(flag: "mid", value: 3, onExecute: {
        lock.lock()
        executionOrder.append("mid")
        lock.unlock()
    }), priority: 5)
    
    queue.resume()
    wait(for: [allFinished], timeout: 3.0)
    
    XCTAssertEqual(executionOrder, ["high", "mid", "low"])
}

func test_equalPriority_preservesFIFOWhenPaused() {
    let queue = OnceTimeoutTaskQueue<Int, TestError>(executeQueue: .global())
    queue.pause()
    
    let allFinished = expectation(description: "all finished")
    allFinished.expectedFulfillmentCount = 3
    var executionOrder: [String] = []
    let lock = NSLock()
    
    queue.taskDidFinish
        .sink { _ in allFinished.fulfill() }
        .store(in: &cancellables)
    
    for flag in ["one", "two", "three"] {
        queue.addTask(makeTask(flag: flag, value: 1, onExecute: {
            lock.lock()
            executionOrder.append(flag)
            lock.unlock()
        }), priority: 1)
    }
    
    queue.resume()
    wait(for: [allFinished], timeout: 3.0)
    
    XCTAssertEqual(executionOrder, ["one", "two", "three"])
}

func test_waitCurrentCompletion_doesNotStopCurrentTask() {
    let queue = OnceTimeoutTaskQueue<Int, TestError>(
        executeQueue: .global(),
        defaultPreemptionStrategy: .waitCurrentCompletion
    )
    let currentStarted = expectation(description: "current started")
    let allowCurrentToFinish = DispatchSemaphore(value: 0)
    let allFinished = expectation(description: "all finished")
    allFinished.expectedFulfillmentCount = 2
    var executionOrder: [String] = []
    var stopCalled = false
    let lock = NSLock()
    
    queue.taskDidFinish
        .sink { _ in allFinished.fulfill() }
        .store(in: &cancellables)
    
    let current = OnceTimeoutTask<Int, TestError>(
        flag: "current",
        executionTimeoutInterval: .seconds(10),
        stopTimeoutInterval: .milliseconds(100),
        execute: { completed in
            lock.lock()
            executionOrder.append("current")
            lock.unlock()
            currentStarted.fulfill()
            allowCurrentToFinish.wait()
            completed(.success(1))
        },
        stop: { stopped in
            stopCalled = true
            stopped()
        }
    )
    let high = makeTask(flag: "high", value: 2, onExecute: {
        lock.lock()
        executionOrder.append("high")
        lock.unlock()
    })
    
    queue.addTask(current, priority: 0)
    wait(for: [currentStarted], timeout: 1.0)
    queue.addTask(high, priority: 10)
    Thread.sleep(forTimeInterval: 0.2)
    
    XCTAssertEqual(executionOrder, ["current"])
    XCTAssertFalse(stopCalled)
    
    allowCurrentToFinish.signal()
    wait(for: [allFinished], timeout: 3.0)
    XCTAssertEqual(executionOrder, ["current", "high"])
}

func test_equalPriority_doesNotPreemptCurrentEvenWithStopStrategy() {
    let queue = OnceTimeoutTaskQueue<Int, TestError>(executeQueue: .global())
    let currentStarted = expectation(description: "current started")
    let allowCurrentToFinish = DispatchSemaphore(value: 0)
    let allFinished = expectation(description: "all finished")
    allFinished.expectedFulfillmentCount = 2
    var executionOrder: [String] = []
    var stopCalled = false
    let lock = NSLock()
    
    queue.taskDidFinish
        .sink { _ in allFinished.fulfill() }
        .store(in: &cancellables)
    
    let current = OnceTimeoutTask<Int, TestError>(
        flag: "current",
        executionTimeoutInterval: .seconds(10),
        stopTimeoutInterval: .milliseconds(100),
        execute: { completed in
            lock.lock()
            executionOrder.append("current")
            lock.unlock()
            currentStarted.fulfill()
            allowCurrentToFinish.wait()
            completed(.success(1))
        },
        stop: { stopped in
            stopCalled = true
            stopped()
        }
    )
    let equal = makeTask(flag: "equal", value: 2, onExecute: {
        lock.lock()
        executionOrder.append("equal")
        lock.unlock()
    })
    
    queue.addTask(current, priority: 5)
    wait(for: [currentStarted], timeout: 1.0)
    queue.addTask(equal, priority: 5, preemptionStrategy: .stopCurrentAndDiscard)
    Thread.sleep(forTimeInterval: 0.2)
    
    XCTAssertEqual(executionOrder, ["current"])
    XCTAssertFalse(stopCalled)
    
    allowCurrentToFinish.signal()
    wait(for: [allFinished], timeout: 3.0)
    XCTAssertEqual(executionOrder, ["current", "equal"])
}

func test_cancelAll_cancelsWaitingAndCurrentAndEmitsEvents() {
    let queue = OnceTimeoutTaskQueue<Int, TestError>(executeQueue: .global())
    let currentStarted = expectation(description: "current started")
    let allFinished = expectation(description: "all finished")
    allFinished.expectedFulfillmentCount = 3
    var eventFlags: [String] = []
    
    queue.taskDidFinish
        .sink { event in
            eventFlags.append(event.flag)
            allFinished.fulfill()
        }
        .store(in: &cancellables)
    
    let current = OnceTimeoutTask<Int, TestError>(
        flag: "current",
        executionTimeoutInterval: .seconds(10),
        stopTimeoutInterval: .milliseconds(100),
        execute: { _ in currentStarted.fulfill() },
        stop: { stopped in stopped() }
    )
    
    queue.addTask(current, priority: 0)
    wait(for: [currentStarted], timeout: 1.0)
    queue.addTask(makeTask(flag: "waiting-high", value: 2), priority: 10)
    queue.addTask(makeTask(flag: "waiting-low", value: 3), priority: 1)
    
    queue.cancelAll()
    wait(for: [allFinished], timeout: 1.0)
    
    XCTAssertEqual(eventFlags, ["waiting-high", "waiting-low", "current"])
    guard case .cancel = doneType(of: current) else {
        XCTFail("Expected current to be cancelled")
        return
    }
}

func test_pause_stopsNextExecutionUntilResume() {
    let queue = OnceTimeoutTaskQueue<Int, TestError>(executeQueue: .global())
    let firstFinished = expectation(description: "first finished")
    var executionOrder: [String] = []
    let lock = NSLock()
    
    queue.taskDidFinish
        .sink { event in
            if event.flag == "first" {
                firstFinished.fulfill()
            }
        }
        .store(in: &cancellables)
    
    queue.addTask(makeTask(flag: "first", value: 1, onExecute: {
        lock.lock()
        executionOrder.append("first")
        lock.unlock()
    }))
    queue.pause()
    queue.addTask(makeTask(flag: "second", value: 2, onExecute: {
        lock.lock()
        executionOrder.append("second")
        lock.unlock()
    }))
    
    wait(for: [firstFinished], timeout: 1.0)
    Thread.sleep(forTimeInterval: 0.2)
    
    XCTAssertEqual(executionOrder, ["first"])
    
    let secondFinished = expectation(description: "second finished")
    queue.taskDidFinish
        .filter { $0.flag == "second" }
        .sink { _ in secondFinished.fulfill() }
        .store(in: &cancellables)
    
    queue.resume()
    wait(for: [secondFinished], timeout: 1.0)
    XCTAssertEqual(executionOrder, ["first", "second"])
}

func test_executionTimeout_triggersNextTaskAndFinishEvent() {
    let queue = OnceTimeoutTaskQueue<Int, TestError>(executeQueue: .global())
    let allFinished = expectation(description: "all finished")
    allFinished.expectedFulfillmentCount = 2
    var eventFlags: [String] = []
    
    queue.taskDidFinish
        .sink { event in
            eventFlags.append(event.flag)
            allFinished.fulfill()
        }
        .store(in: &cancellables)
    
    let timeoutTask = OnceTimeoutTask<Int, TestError>(
        flag: "timeout",
        executionTimeoutInterval: .milliseconds(80),
        stopTimeoutInterval: .milliseconds(100),
        execute: { _ in },
        stop: { stopped in stopped() }
    )
    let nextTask = makeTask(flag: "next", value: 2)
    
    queue.addTask(timeoutTask)
    queue.addTask(nextTask)
    
    wait(for: [allFinished], timeout: 2.0)
    XCTAssertEqual(eventFlags, ["timeout", "next"])
    guard case .executionTimeout = doneType(of: timeoutTask) else {
        XCTFail("Expected executionTimeout")
        return
    }
}
```

- [ ] **Step 3: Run queue tests and verify they fail before queue implementation**

Run:

```bash
rtk xcodebuild test -project Project/RYKit.xcodeproj -scheme RYKitTests -destination 'platform=macOS' -only-testing:RYKitTests/OnceTimeoutTaskQueueTests
```

Expected: FAIL with compiler errors for missing `PreemptionStrategy`, `TaskFinishEvent`, `taskDidFinish`, `addTask(_:priority:preemptionStrategy:)`, and missing new queue initializer.

- [ ] **Step 4: Replace queue inheritance with priority storage and finish events**

Replace the contents of `Classes/Core/TimeoutTask/OnceTimeoutTaskQueue.swift` with the baseline implementation below. This version supports priority ordering, FIFO ties, finish events, pause/resume, execution timeout progression, and default wait strategy. Preemptive stop strategies are added in Task 3.

```swift
//
//  OnceTimeoutTaskQueue.swift
//  RYKit
//
//  Created by mao rui on 2026/1/19.
//

import Combine
import Foundation

public class OnceTimeoutTaskQueue<T, E: Error> {
    public enum PreemptionStrategy {
        case stopCurrentAndDiscard
        case waitCurrentCompletion
        case stopCurrentAndRequeue
    }
    
    public struct TaskFinishEvent {
        public let flag: String
        public let task: OnceTimeoutTask<T, E>
        public let doneType: OnceTimeoutTask<T, E>.DoneType
    }
    
    private struct QueuedTask {
        let task: OnceTimeoutTask<T, E>
        let priority: Int
        let sequence: Int
    }
    
    public let taskDidFinish = PassthroughSubject<TaskFinishEvent, Never>()
    
    private let executeQueue: DispatchQueue
    private let defaultPreemptionStrategy: PreemptionStrategy
    private let timeoutQueue = DispatchQueue(label: "com.rykit.OnceTimeoutTaskQueue.timeoutQueue", qos: .userInitiated, attributes: .concurrent, autoreleaseFrequency: .workItem)
    private let lock = UnfairLock()
    private var paused: Bool = false
    private var sequence: Int = 0
    private var waiting: [QueuedTask] = []
    private var current: QueuedTask?
    
    public init(
        executeQueue: DispatchQueue,
        defaultPreemptionStrategy: PreemptionStrategy = .waitCurrentCompletion
    ) {
        self.executeQueue = executeQueue
        self.defaultPreemptionStrategy = defaultPreemptionStrategy
    }
    
    public func addTask(
        _ task: OnceTimeoutTask<T, E>,
        priority: Int = 0,
        preemptionStrategy: PreemptionStrategy? = nil
    ) {
        guard !task.state.hasStarted else {
            return
        }
        
        task.onDone = { [weak self, weak task] doneType in
            guard let task else { return }
            self?.handleTaskDone(task, doneType: doneType)
        }
        
        let item = makeQueuedTask(task: task, priority: priority)
        let taskToStart: QueuedTask?
        
        lock.lock()
        insert(item)
        taskToStart = takeNextIfPossible()
        lock.unlock()
        
        start(taskToStart)
    }
    
    public func pause() {
        lock.lock()
        paused = true
        lock.unlock()
    }
    
    public func resume() {
        let taskToStart: QueuedTask?
        
        lock.lock()
        guard paused else {
            lock.unlock()
            return
        }
        paused = false
        taskToStart = takeNextIfPossible()
        lock.unlock()
        
        start(taskToStart)
    }
    
    public func cancelAll() {
        let itemsToCancel: [QueuedTask]
        let currentToCancel: QueuedTask?
        
        lock.lock()
        itemsToCancel = waiting
        waiting.removeAll()
        currentToCancel = current
        current = nil
        lock.unlock()
        
        let events = (itemsToCancel + [currentToCancel].compactMap { $0 }).compactMap { item -> TaskFinishEvent? in
            guard let doneType = item.task.cancelFromQueue() else {
                return nil
            }
            return TaskFinishEvent(flag: item.task.flag, task: item.task, doneType: doneType)
        }
        publish(events)
    }
    
    private func makeQueuedTask(task: OnceTimeoutTask<T, E>, priority: Int) -> QueuedTask {
        lock.lock()
        sequence += 1
        let nextSequence = sequence
        lock.unlock()
        return QueuedTask(task: task, priority: priority, sequence: nextSequence)
    }
    
    private func insert(_ item: QueuedTask) {
        guard let index = waiting.firstIndex(where: { queued in
            item.priority > queued.priority || (item.priority == queued.priority && item.sequence < queued.sequence)
        }) else {
            waiting.append(item)
            return
        }
        waiting.insert(item, at: index)
    }
    
    private func takeNextIfPossible() -> QueuedTask? {
        guard !paused, current == nil, !waiting.isEmpty else {
            return nil
        }
        let next = waiting.removeFirst()
        current = next
        return next
    }
    
    private func start(_ item: QueuedTask?) {
        guard let item else {
            return
        }
        item.task.perform(by: executeQueue, timeoutQueue: timeoutQueue)
    }
    
    private func handleTaskDone(_ task: OnceTimeoutTask<T, E>, doneType: OnceTimeoutTask<T, E>.DoneType) {
        let event: TaskFinishEvent?
        let taskToStart: QueuedTask?
        
        lock.lock()
        guard let current, current.task === task else {
            lock.unlock()
            return
        }
        self.current = nil
        event = TaskFinishEvent(flag: task.flag, task: task, doneType: doneType)
        taskToStart = takeNextIfPossible()
        lock.unlock()
        
        publish([event].compactMap { $0 })
        start(taskToStart)
    }
    
    private func publish(_ events: [TaskFinishEvent]) {
        for event in events {
            taskDidFinish.send(event)
        }
    }
}
```

- [ ] **Step 5: Run queue baseline tests and verify they pass**

Run:

```bash
rtk xcodebuild test -project Project/RYKit.xcodeproj -scheme RYKitTests -destination 'platform=macOS' -only-testing:RYKitTests/OnceTimeoutTaskQueueTests
```

Expected: PASS for the queue tests written in this task.

- [ ] **Step 6: Commit Task 2**

```bash
rtk git add Classes/Core/TimeoutTask/OnceTimeoutTaskQueue.swift Project/RYKitTests/TimeoutTaskTests.swift
rtk git commit -m "Add priority queue finish events" -m "The queue needs private priority metadata and finish events before preemptive stop strategies can be layered on safely." -m "Constraint: taskDidFinish fires only after queue ownership ends" -m "Rejected: Inheriting Queue storage | inherited enqueue and dequeue bypass priority metadata" -m "Confidence: high" -m "Scope-risk: moderate" -m "Tested: xcodebuild OnceTimeoutTaskQueueTests"
```

---

### Task 3: Implement Stop Coordination And Preemption Strategies

**Files:**
- Modify: `Project/RYKitTests/TimeoutTaskTests.swift`
- Modify: `Classes/Core/TimeoutTask/OnceTimeoutTaskQueue.swift`

- [ ] **Step 1: Add preemption tests to `OnceTimeoutTaskQueueTests`**

Append these tests to `OnceTimeoutTaskQueueTests`:

```swift
func test_stopCurrentAndDiscard_waitsForStoppedBeforeStartingHighPriorityTask() {
    let queue = OnceTimeoutTaskQueue<Int, TestError>(executeQueue: .global())
    let currentStarted = expectation(description: "current started")
    let highStarted = expectation(description: "high started")
    var stoppedCallback: (() -> Void)?
    var executionOrder: [String] = []
    var eventFlags: [String] = []
    let lock = NSLock()
    
    queue.taskDidFinish
        .sink { event in
            lock.lock()
            eventFlags.append(event.flag)
            lock.unlock()
        }
        .store(in: &cancellables)
    
    let current = OnceTimeoutTask<Int, TestError>(
        flag: "current",
        executionTimeoutInterval: .seconds(10),
        stopTimeoutInterval: .seconds(1),
        execute: { _ in
            lock.lock()
            executionOrder.append("current")
            lock.unlock()
            currentStarted.fulfill()
        },
        stop: { stopped in
            stoppedCallback = stopped
        }
    )
    let high = makeTask(flag: "high", value: 2, onExecute: {
        lock.lock()
        executionOrder.append("high")
        lock.unlock()
        highStarted.fulfill()
    })
    
    queue.addTask(current, priority: 0)
    wait(for: [currentStarted], timeout: 1.0)
    queue.addTask(high, priority: 10, preemptionStrategy: .stopCurrentAndDiscard)
    Thread.sleep(forTimeInterval: 0.2)
    
    XCTAssertEqual(executionOrder, ["current"])
    
    stoppedCallback?()
    wait(for: [highStarted], timeout: 1.0)
    Thread.sleep(forTimeInterval: 0.1)
    
    XCTAssertEqual(executionOrder, ["current", "high"])
    XCTAssertEqual(eventFlags, ["current", "high"])
}

func test_stopCurrentAndDiscard_continuesAfterStopTimeout() {
    let queue = OnceTimeoutTaskQueue<Int, TestError>(executeQueue: .global())
    let currentStarted = expectation(description: "current started")
    let highStarted = expectation(description: "high started")
    var executionOrder: [String] = []
    let lock = NSLock()
    
    let current = OnceTimeoutTask<Int, TestError>(
        flag: "current",
        executionTimeoutInterval: .seconds(10),
        stopTimeoutInterval: .milliseconds(120),
        execute: { _ in
            lock.lock()
            executionOrder.append("current")
            lock.unlock()
            currentStarted.fulfill()
        },
        stop: { _ in }
    )
    let high = makeTask(flag: "high", value: 2, onExecute: {
        lock.lock()
        executionOrder.append("high")
        lock.unlock()
        highStarted.fulfill()
    })
    
    queue.addTask(current, priority: 0)
    wait(for: [currentStarted], timeout: 1.0)
    queue.addTask(high, priority: 10, preemptionStrategy: .stopCurrentAndDiscard)
    
    wait(for: [highStarted], timeout: 2.0)
    XCTAssertEqual(executionOrder, ["current", "high"])
}

func test_stopCurrentAndRequeue_doesNotEmitIntermediateStopAndRunsStoppedTaskAgain() {
    let queue = OnceTimeoutTaskQueue<Int, TestError>(executeQueue: .global())
    let firstCurrentStarted = expectation(description: "current first start")
    let highFinished = expectation(description: "high finished")
    let currentFinished = expectation(description: "current final finish")
    var stoppedCallback: (() -> Void)?
    var currentRunCount = 0
    var executionOrder: [String] = []
    var eventFlags: [String] = []
    let lock = NSLock()
    
    queue.taskDidFinish
        .sink { event in
            lock.lock()
            eventFlags.append(event.flag)
            lock.unlock()
            if event.flag == "high" {
                highFinished.fulfill()
            }
            if event.flag == "current" {
                currentFinished.fulfill()
            }
        }
        .store(in: &cancellables)
    
    let current = OnceTimeoutTask<Int, TestError>(
        flag: "current",
        executionTimeoutInterval: .seconds(10),
        stopTimeoutInterval: .seconds(1),
        execute: { completed in
            lock.lock()
            currentRunCount += 1
            let run = currentRunCount
            executionOrder.append("current-\(run)")
            lock.unlock()
            
            if run == 1 {
                firstCurrentStarted.fulfill()
            } else {
                completed(.success(1))
            }
        },
        stop: { stopped in
            stoppedCallback = stopped
        }
    )
    let high = makeTask(flag: "high", value: 2, onExecute: {
        lock.lock()
        executionOrder.append("high")
        lock.unlock()
    })
    
    queue.addTask(current, priority: 0)
    wait(for: [firstCurrentStarted], timeout: 1.0)
    queue.addTask(high, priority: 10, preemptionStrategy: .stopCurrentAndRequeue)
    stoppedCallback?()
    
    wait(for: [highFinished, currentFinished], timeout: 3.0)
    
    XCTAssertEqual(executionOrder, ["current-1", "high", "current-2"])
    XCTAssertEqual(eventFlags, ["high", "current"])
}

func test_cancelAll_duringStopWaitAbandonsPendingPreemptionAndEmitsStoppedTaskOnStopCompletion() {
    let queue = OnceTimeoutTaskQueue<Int, TestError>(executeQueue: .global())
    let currentStarted = expectation(description: "current started")
    let stoppedTaskFinished = expectation(description: "stopped task finished")
    var stoppedCallback: (() -> Void)?
    var eventFlags: [String] = []
    
    queue.taskDidFinish
        .sink { event in
            eventFlags.append(event.flag)
            if event.flag == "current" {
                stoppedTaskFinished.fulfill()
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
    queue.cancelAll()
    stoppedCallback?()
    
    wait(for: [stoppedTaskFinished], timeout: 1.0)
    Thread.sleep(forTimeInterval: 0.2)
    
    XCTAssertEqual(eventFlags, ["high", "current"])
}
```

- [ ] **Step 2: Run preemption tests and verify they fail before implementation**

Run:

```bash
rtk xcodebuild test -project Project/RYKit.xcodeproj -scheme RYKitTests -destination 'platform=macOS' -only-testing:RYKitTests/OnceTimeoutTaskQueueTests
```

Expected: FAIL because `.stopCurrentAndDiscard` and `.stopCurrentAndRequeue` currently behave like `.waitCurrentCompletion`.

- [ ] **Step 3: Extend `OnceTimeoutTaskQueue` with stop coordination**

In `Classes/Core/TimeoutTask/OnceTimeoutTaskQueue.swift`, add these private declarations after `current`:

```swift
private enum StopDisposition {
    case discard
    case requeue
}

private var stopping: QueuedTask?
private var stopDisposition: StopDisposition?
```

Replace `addTask` with:

```swift
public func addTask(
    _ task: OnceTimeoutTask<T, E>,
    priority: Int = 0,
    preemptionStrategy: PreemptionStrategy? = nil
) {
    guard !task.state.hasStarted else {
        return
    }
    
    task.onDone = { [weak self, weak task] doneType in
        guard let task else { return }
        self?.handleTaskDone(task, doneType: doneType)
    }
    
    let item = makeQueuedTask(task: task, priority: priority)
    let strategy = preemptionStrategy ?? defaultPreemptionStrategy
    var taskToStart: QueuedTask?
    var stopRequest: (() -> Void)?
    
    lock.lock()
    if let current, item.priority > current.priority {
        insert(item)
        switch strategy {
        case .waitCurrentCompletion:
            break
        case .stopCurrentAndDiscard:
            stopRequest = prepareStopLocked(disposition: .discard)
        case .stopCurrentAndRequeue:
            stopRequest = prepareStopLocked(disposition: .requeue)
        }
    } else {
        insert(item)
    }
    taskToStart = takeNextIfPossible()
    lock.unlock()
    
    stopRequest?()
    start(taskToStart)
}
```

Add this helper:

```swift
private func prepareStopLocked(disposition: StopDisposition) -> (() -> Void)? {
    guard stopping == nil, let current else {
        return nil
    }
    guard let request = current.task.makeStopRequest(timeoutQueue: timeoutQueue, onStopped: { [weak self, weak task = current.task] in
        guard let task else { return }
        self?.handleTaskStopped(task)
    }) else {
        return nil
    }
    self.current = nil
    stopping = current
    stopDisposition = disposition
    return request
}
```

Replace `takeNextIfPossible` with:

```swift
private func takeNextIfPossible() -> QueuedTask? {
    guard !paused, current == nil, stopping == nil, !waiting.isEmpty else {
        return nil
    }
    let next = waiting.removeFirst()
    current = next
    return next
}
```

Add `handleTaskStopped`:

```swift
private func handleTaskStopped(_ task: OnceTimeoutTask<T, E>) {
    let event: TaskFinishEvent?
    let taskToStart: QueuedTask?
    
    lock.lock()
    guard let stopping, stopping.task === task else {
        lock.unlock()
        return
    }
    
    switch stopDisposition {
    case .requeue:
        if stopping.task.resetForRequeue() {
            insert(makeQueuedTaskLocked(task: stopping.task, priority: stopping.priority))
        }
        event = nil
    case .discard, .none:
        event = TaskFinishEvent(flag: task.flag, task: task, doneType: .stop)
    }
    
    self.stopping = nil
    stopDisposition = nil
    taskToStart = takeNextIfPossible()
    lock.unlock()
    
    publish([event].compactMap { $0 })
    start(taskToStart)
}
```

Add a lock-held sequence helper so `handleTaskStopped` can requeue without reentering the lock:

```swift
private func makeQueuedTaskLocked(task: OnceTimeoutTask<T, E>, priority: Int) -> QueuedTask {
    sequence += 1
    return QueuedTask(task: task, priority: priority, sequence: sequence)
}
```

Replace `makeQueuedTask` with:

```swift
private func makeQueuedTask(task: OnceTimeoutTask<T, E>, priority: Int) -> QueuedTask {
    lock.lock()
    let item = makeQueuedTaskLocked(task: task, priority: priority)
    lock.unlock()
    return item
}
```

- [ ] **Step 4: Update `cancelAll` for stop-wait abandonment**

Replace `cancelAll` with:

```swift
public func cancelAll() {
    let waitingToCancel: [QueuedTask]
    let currentToCancel: QueuedTask?
    let stoppedToDiscardLater: Bool
    
    lock.lock()
    waitingToCancel = waiting
    waiting.removeAll()
    currentToCancel = current
    current = nil
    stoppedToDiscardLater = stopping != nil
    if stoppedToDiscardLater {
        stopDisposition = .discard
    }
    lock.unlock()
    
    let immediateItems = waitingToCancel + [currentToCancel].compactMap { $0 }
    let events = immediateItems.compactMap { item -> TaskFinishEvent? in
        guard let doneType = item.task.cancelFromQueue() else {
            return nil
        }
        return TaskFinishEvent(flag: item.task.flag, task: item.task, doneType: doneType)
    }
    publish(events)
}
```

- [ ] **Step 5: Run queue tests and verify preemption behavior passes**

Run:

```bash
rtk xcodebuild test -project Project/RYKit.xcodeproj -scheme RYKitTests -destination 'platform=macOS' -only-testing:RYKitTests/OnceTimeoutTaskQueueTests
```

Expected: PASS for `OnceTimeoutTaskQueueTests`.

- [ ] **Step 6: Commit Task 3**

```bash
rtk git add Classes/Core/TimeoutTask/OnceTimeoutTaskQueue.swift Project/RYKitTests/TimeoutTaskTests.swift
rtk git commit -m "Coordinate priority preemption stops" -m "High-priority queue insertions can now wait for stopped callbacks or stop timeout, then discard or requeue the interrupted task according to the selected strategy." -m "Constraint: Requeued tasks must not emit taskDidFinish for the intermediate stop" -m "Confidence: high" -m "Scope-risk: moderate" -m "Tested: xcodebuild OnceTimeoutTaskQueueTests"
```

---

### Task 4: Update README TimeoutTask Examples

**Files:**
- Modify: `README.md`

- [ ] **Step 1: Update English TimeoutTask example**

Replace the English `TimeoutTask` snippet with:

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

Replace the English queue snippet with:

```swift
let queue = OnceTimeoutTaskQueue<String, Error>(
    executeQueue: .main,
    defaultPreemptionStrategy: .waitCurrentCompletion
)
let cancellable = queue.taskDidFinish.sink { event in
    print(event.flag, event.doneType)
}
queue.addTask(task, priority: 10)
```

- [ ] **Step 2: Update Chinese TimeoutTask example**

Replace the Chinese `TimeoutTask` snippet with the same Swift code used in Step 1. Keep the surrounding Chinese heading and prose unchanged.

- [ ] **Step 3: Scan README for removed API names**

Run:

```bash
rtk rg -n "timeoutInterval|done:|\\.timeout" README.md Project/RYKitTests/TimeoutTaskTests.swift Classes/Core/TimeoutTask
```

Expected: no matches for removed TimeoutTask API usage. The command may still match prose in the design and plan files; do not include `docs/` in this scan.

- [ ] **Step 4: Commit Task 4**

```bash
rtk git add README.md
rtk git commit -m "Update timeout task examples" -m "The public timeout task examples need to show explicit flags, execution timeout naming, required stop callbacks, priority insertion, and queue finish-event observation." -m "Constraint: README must not show removed init done callback usage" -m "Confidence: high" -m "Scope-risk: narrow" -m "Tested: rg removed TimeoutTask API usage in README and source tests"
```

---

### Task 5: Full Verification And Cleanup

**Files:**
- Verify: `Classes/Core/TimeoutTask/OnceTimeoutTask.swift`
- Verify: `Classes/Core/TimeoutTask/OnceTimeoutTaskQueue.swift`
- Verify: `Project/RYKitTests/TimeoutTaskTests.swift`
- Verify: `README.md`

- [ ] **Step 1: Run focused task tests**

Run:

```bash
rtk xcodebuild test -project Project/RYKit.xcodeproj -scheme RYKitTests -destination 'platform=macOS' -only-testing:RYKitTests/OnceTimeoutTaskTests
```

Expected: PASS.

- [ ] **Step 2: Run focused queue tests**

Run:

```bash
rtk xcodebuild test -project Project/RYKit.xcodeproj -scheme RYKitTests -destination 'platform=macOS' -only-testing:RYKitTests/OnceTimeoutTaskQueueTests
```

Expected: PASS.

- [ ] **Step 3: Run full Xcode test suite**

Run:

```bash
rtk xcodebuild test -project Project/RYKit.xcodeproj -scheme RYKitTests -destination 'platform=macOS'
```

Expected: PASS.

- [ ] **Step 4: Run Swift package build**

Run:

```bash
rtk swift build
```

Expected: PASS.

- [ ] **Step 5: Check final diff scope**

Run:

```bash
rtk git status --short
rtk git diff --stat
```

Expected: only the intended TimeoutTask source, TimeoutTask tests, and README changes remain uncommitted after Task 4 commits. If all implementation tasks committed cleanly, only unrelated pre-existing workspace changes may appear.

- [ ] **Step 6: Final implementation commit if verification required small fixes**

Use this only if Step 1-5 required additional fixes after Task 4:

```bash
rtk git add Classes/Core/TimeoutTask/OnceTimeoutTask.swift Classes/Core/TimeoutTask/OnceTimeoutTaskQueue.swift Project/RYKitTests/TimeoutTaskTests.swift README.md
rtk git commit -m "Stabilize timeout task priority queue" -m "Final verification fixes keep the stop-aware priority queue behavior aligned with tests and documentation." -m "Confidence: high" -m "Scope-risk: narrow" -m "Tested: xcodebuild focused task tests, focused queue tests, full RYKitTests, swift build"
```
