//
//  TimeoutTaskTests.swift
//  RYKitTests
//
//  Created by Claude on 2026/1/21.
//

import Combine
import XCTest
@testable import RYKit

// MARK: - OnceTimeoutTask Tests

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
            XCTFail("Expected completed with error")
            return
        }
        XCTAssertThrowsError(try result.get())
    }

    func test_executionTimeout_updatesState() {
        let timedOut = expectation(description: "timed out")
        let task = OnceTimeoutTask<Int, TestError>(
            flag: "timeout",
            executionTimeoutInterval: .milliseconds(80),
            stopTimeoutInterval: .milliseconds(100),
            execute: { _ in },
            stop: { stopped in stopped() }
        )
        task.onDone = { _ in
            timedOut.fulfill()
        }

        task.perform(by: .global(), timeoutQueue: .global())
        wait(for: [timedOut], timeout: 1.0)

        guard case .executionTimeout = doneType(of: task) else {
            XCTFail("Expected executionTimeout, got \(String(describing: doneType(of: task)))")
            return
        }
    }

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

    func test_staleCompletionAfterResetForRequeue_doesNotCompleteLaterRun() {
        let firstRunStarted = expectation(description: "first run started")
        let secondRunStarted = expectation(description: "second run started")
        let executeQueue = DispatchQueue(label: "OnceTimeoutTaskTests.staleCompletion.execute")
        let timeoutQueue = DispatchQueue(label: "OnceTimeoutTaskTests.staleCompletion.timeout")
        let lock = NSLock()
        var completions: [((Result<Int, TestError>) -> Void)] = []

        let task = OnceTimeoutTask<Int, TestError>(
            flag: "stale-completion",
            executionTimeoutInterval: .seconds(10),
            stopTimeoutInterval: .never,
            execute: { completed in
                lock.lock()
                completions.append(completed)
                let count = completions.count
                lock.unlock()

                if count == 1 {
                    firstRunStarted.fulfill()
                } else if count == 2 {
                    secondRunStarted.fulfill()
                }
            },
            stop: { _ in }
        )

        task.perform(by: executeQueue, timeoutQueue: timeoutQueue)
        wait(for: [firstRunStarted], timeout: 1.0)
        let stopRequest = task.makeStopRequest(timeoutQueue: timeoutQueue, onStopped: {})
        XCTAssertNotNil(stopRequest)
        stopRequest?()
        XCTAssertTrue(task.resetForRequeue())

        task.perform(by: executeQueue, timeoutQueue: timeoutQueue)
        wait(for: [secondRunStarted], timeout: 1.0)

        lock.lock()
        let firstCompletion = completions[0]
        let secondCompletion = completions[1]
        lock.unlock()

        firstCompletion(.success(1))
        Thread.sleep(forTimeInterval: 0.05)
        XCTAssertFalse(task.state.isDone)

        secondCompletion(.success(2))
        assertCompletedSuccess(doneType(of: task), equals: 2)
    }

    func test_staleStoppedAfterResetForRequeue_doesNotFinishLaterStopRequest() {
        let firstRunStarted = expectation(description: "first run started")
        let secondRunStarted = expectation(description: "second run started")
        let firstStopCaptured = expectation(description: "first stop captured")
        let secondStopCaptured = expectation(description: "second stop captured")
        let secondStoppedDidFinish = expectation(description: "second stopped did finish")
        let executeQueue = DispatchQueue(label: "OnceTimeoutTaskTests.staleStopped.execute")
        let timeoutQueue = DispatchQueue(label: "OnceTimeoutTaskTests.staleStopped.timeout")
        let lock = NSLock()
        var runCount = 0
        var finishCount = 0
        var stoppedCallbacks: [OnceTimeoutTask<Int, TestError>.Stopped] = []

        let task = OnceTimeoutTask<Int, TestError>(
            flag: "stale-stopped",
            executionTimeoutInterval: .seconds(10),
            stopTimeoutInterval: .never,
            execute: { _ in
                lock.lock()
                runCount += 1
                let count = runCount
                lock.unlock()

                if count == 1 {
                    firstRunStarted.fulfill()
                } else if count == 2 {
                    secondRunStarted.fulfill()
                }
            },
            stop: { stopped in
                lock.lock()
                stoppedCallbacks.append(stopped)
                let count = stoppedCallbacks.count
                lock.unlock()

                if count == 1 {
                    firstStopCaptured.fulfill()
                } else if count == 2 {
                    secondStopCaptured.fulfill()
                }
            }
        )

        task.perform(by: executeQueue, timeoutQueue: timeoutQueue)
        wait(for: [firstRunStarted], timeout: 1.0)
        let firstStopRequest = task.makeStopRequest(timeoutQueue: timeoutQueue, onStopped: {})
        XCTAssertNotNil(firstStopRequest)
        firstStopRequest?()
        wait(for: [firstStopCaptured], timeout: 1.0)
        XCTAssertTrue(task.resetForRequeue())

        task.perform(by: executeQueue, timeoutQueue: timeoutQueue)
        wait(for: [secondRunStarted], timeout: 1.0)
        let secondStopRequest = task.makeStopRequest(timeoutQueue: timeoutQueue) {
            lock.lock()
            finishCount += 1
            lock.unlock()
            secondStoppedDidFinish.fulfill()
        }
        XCTAssertNotNil(secondStopRequest)
        secondStopRequest?()
        wait(for: [secondStopCaptured], timeout: 1.0)

        lock.lock()
        let firstStopped = stoppedCallbacks[0]
        let secondStopped = stoppedCallbacks[1]
        lock.unlock()

        firstStopped()
        Thread.sleep(forTimeInterval: 0.1)
        lock.lock()
        let countAfterStaleStopped = finishCount
        lock.unlock()
        XCTAssertEqual(countAfterStaleStopped, 0)

        secondStopped()
        wait(for: [secondStoppedDidFinish], timeout: 1.0)
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

// MARK: - OnceTimeoutTaskQueue Tests

final class OnceTimeoutTaskQueueTests: XCTestCase {

    enum TestError: Error {
        case failed
    }

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
        let duplicateCurrentEvent = expectation(description: "duplicate current event")
        duplicateCurrentEvent.isInverted = true
        var eventFlags: [String] = []
        var currentEventCount = 0
        var capturedComplete: OnceTimeoutTask<Int, TestError>.Completed?

        queue.taskDidFinish
            .sink { event in
                eventFlags.append(event.flag)
                if event.flag == "current" {
                    currentEventCount += 1
                    if currentEventCount > 1 {
                        duplicateCurrentEvent.fulfill()
                    }
                }
                allFinished.fulfill()
            }
            .store(in: &cancellables)

        let current = OnceTimeoutTask<Int, TestError>(
            flag: "current",
            executionTimeoutInterval: .seconds(10),
            stopTimeoutInterval: .milliseconds(100),
            execute: { completed in
                capturedComplete = completed
                currentStarted.fulfill()
            },
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
        capturedComplete?(.success(1))
        wait(for: [duplicateCurrentEvent], timeout: 0.2)
        XCTAssertEqual(currentEventCount, 1)
    }

    func test_cancelAllDuringPublicStopWaitKeepsCurrentUntilStoppedAndCancelsWaiting() {
        let queue = OnceTimeoutTaskQueue<Int, TestError>(executeQueue: .global())
        let currentStarted = expectation(description: "current started")
        let stopCaptured = expectation(description: "stop captured")
        let waitingCancelled = expectation(description: "waiting cancelled")
        let currentFinished = expectation(description: "current finished")
        let waitingStarted = expectation(description: "waiting started")
        waitingStarted.isInverted = true
        var capturedStopped: OnceTimeoutTask<Int, TestError>.Stopped?
        var eventFlags: [String] = []
        var currentDoneType: OnceTimeoutTask<Int, TestError>.DoneType?
        let lock = NSLock()

        queue.taskDidFinish
            .sink { event in
                lock.lock()
                eventFlags.append(event.flag)
                lock.unlock()

                if event.flag == "waiting" {
                    waitingCancelled.fulfill()
                } else if event.flag == "current" {
                    currentDoneType = event.doneType
                    currentFinished.fulfill()
                }
            }
            .store(in: &cancellables)

        let current = OnceTimeoutTask<Int, TestError>(
            flag: "current",
            executionTimeoutInterval: .seconds(10),
            stopTimeoutInterval: .seconds(10),
            execute: { _ in currentStarted.fulfill() },
            stop: { stopped in
                lock.lock()
                capturedStopped = stopped
                lock.unlock()
                stopCaptured.fulfill()
            }
        )
        let waiting = makeTask(flag: "waiting", value: 2, onExecute: {
            waitingStarted.fulfill()
        })

        queue.addTask(current)
        wait(for: [currentStarted], timeout: 1.0)
        queue.addTask(waiting)
        current.stop()
        wait(for: [stopCaptured], timeout: 1.0)

        queue.cancelAll()
        wait(for: [waitingCancelled], timeout: 1.0)
        wait(for: [waitingStarted], timeout: 0.2)

        lock.lock()
        let stopped = capturedStopped
        let flagsBeforeStopped = eventFlags
        lock.unlock()

        XCTAssertEqual(flagsBeforeStopped, ["waiting"])
        stopped?()

        wait(for: [currentFinished], timeout: 1.0)
        guard case .stop = currentDoneType else {
            XCTFail("Expected current finish event to be stop")
            return
        }

        lock.lock()
        let flagsAfterStopped = eventFlags
        lock.unlock()
        XCTAssertEqual(flagsAfterStopped, ["waiting", "current"])
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

    func test_finishSubscriberCanPauseBeforeNextTaskStarts() {
        let queue = OnceTimeoutTaskQueue<Int, TestError>(executeQueue: .global())
        let firstStarted = expectation(description: "first started")
        let firstFinished = expectation(description: "first finished")
        let secondStartedBeforeResume = expectation(description: "second started before resume")
        secondStartedBeforeResume.isInverted = true
        let secondFinished = expectation(description: "second finished")
        let allowFirstToFinish = DispatchSemaphore(value: 0)
        var executionOrder: [String] = []
        let lock = NSLock()

        queue.taskDidFinish
            .sink { event in
                if event.flag == "first" {
                    queue.pause()
                    firstFinished.fulfill()
                } else if event.flag == "second" {
                    secondFinished.fulfill()
                }
            }
            .store(in: &cancellables)

        let first = OnceTimeoutTask<Int, TestError>(
            flag: "first",
            executionTimeoutInterval: .seconds(10),
            stopTimeoutInterval: .milliseconds(100),
            execute: { completed in
                lock.lock()
                executionOrder.append("first")
                lock.unlock()
                firstStarted.fulfill()
                allowFirstToFinish.wait()
                completed(.success(1))
            },
            stop: { stopped in stopped() }
        )
        let second = makeTask(flag: "second", value: 2, onExecute: {
            lock.lock()
            executionOrder.append("second")
            lock.unlock()
            secondStartedBeforeResume.fulfill()
        })

        queue.addTask(first)
        wait(for: [firstStarted], timeout: 1.0)
        queue.addTask(second)
        allowFirstToFinish.signal()

        wait(for: [firstFinished], timeout: 1.0)
        wait(for: [secondStartedBeforeResume], timeout: 0.2)
        XCTAssertEqual(executionOrder, ["first"])

        queue.resume()
        wait(for: [secondFinished], timeout: 1.0)
        XCTAssertEqual(executionOrder, ["first", "second"])
    }

    func test_publicStopWaitsForStoppedBeforeQueueProgresses() {
        let queue = OnceTimeoutTaskQueue<Int, TestError>(executeQueue: .global())
        let currentStarted = expectation(description: "current started")
        let stopCaptured = expectation(description: "stop captured")
        let currentFinished = expectation(description: "current finished")
        let secondStartedBeforeStopped = expectation(description: "second started before stopped")
        secondStartedBeforeStopped.isInverted = true
        let secondFinished = expectation(description: "second finished")
        var capturedStopped: OnceTimeoutTask<Int, TestError>.Stopped?
        var currentDoneType: OnceTimeoutTask<Int, TestError>.DoneType?
        var executionOrder: [String] = []
        let lock = NSLock()

        queue.taskDidFinish
            .sink { event in
                if event.flag == "current" {
                    currentDoneType = event.doneType
                    currentFinished.fulfill()
                } else if event.flag == "second" {
                    secondFinished.fulfill()
                }
            }
            .store(in: &cancellables)

        let current = OnceTimeoutTask<Int, TestError>(
            flag: "current",
            executionTimeoutInterval: .seconds(10),
            stopTimeoutInterval: .seconds(10),
            execute: { _ in
                lock.lock()
                executionOrder.append("current")
                lock.unlock()
                currentStarted.fulfill()
            },
            stop: { stopped in
                lock.lock()
                capturedStopped = stopped
                lock.unlock()
                stopCaptured.fulfill()
            }
        )
        let second = makeTask(flag: "second", value: 2, onExecute: {
            lock.lock()
            executionOrder.append("second")
            lock.unlock()
            secondStartedBeforeStopped.fulfill()
        })

        queue.addTask(current)
        wait(for: [currentStarted], timeout: 1.0)
        queue.addTask(second)
        current.stop()

        wait(for: [stopCaptured], timeout: 1.0)
        wait(for: [secondStartedBeforeStopped], timeout: 0.2)
        XCTAssertEqual(executionOrder, ["current"])

        lock.lock()
        let stopped = capturedStopped
        lock.unlock()
        stopped?()

        wait(for: [currentFinished, secondFinished], timeout: 1.0)
        guard case .stop = currentDoneType else {
            XCTFail("Expected current finish event to be stop")
            return
        }
        XCTAssertEqual(executionOrder, ["current", "second"])
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

        queue.addTask(current, priority: 0)
        wait(for: [firstCurrentStarted], timeout: 1.0)
        queue.addTask(high, priority: 10, preemptionStrategy: .stopCurrentAndRequeue)

        guard case .waitingRestart(stopped: false) = current.state else {
            XCTFail("Expected waitingRestart(false), got \(current.state)")
            return
        }

        stoppedCallback?()

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

        wait(for: [highFinished, currentFinished], timeout: 3.0)

        XCTAssertEqual(executionOrder, ["current-1", "high", "current-2"])
        XCTAssertEqual(eventFlags, ["high", "current"])
    }

    func test_cancelAllDuringWaitingRestartFalseFinishesAsCancelAfterStopped() {
        let queue = OnceTimeoutTaskQueue<Int, TestError>(executeQueue: .global())
        let currentStarted = expectation(description: "current started")
        let currentFinished = expectation(description: "current finished")
        let currentFinishedBeforeStopped = expectation(description: "current finished before stopped")
        currentFinishedBeforeStopped.isInverted = true
        var stoppedCallback: (() -> Void)?
        var eventDoneType: OnceTimeoutTask<Int, TestError>.DoneType?

        queue.taskDidFinish
            .sink { event in
                if event.flag == "current" {
                    eventDoneType = event.doneType
                    currentFinished.fulfill()
                    currentFinishedBeforeStopped.fulfill()
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

        wait(for: [currentFinishedBeforeStopped], timeout: 0.2)
        XCTAssertNil(eventDoneType)

        stoppedCallback?()
        wait(for: [currentFinished], timeout: 1.0)

        guard case .cancel = eventDoneType else {
            XCTFail("Expected cancel finish event")
            return
        }
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
}

private extension OnceTimeoutTask {
    func setWaitingRestartForTest(stopped: Bool) {
        setWaitingRestart(stopped: stopped)
    }
}
