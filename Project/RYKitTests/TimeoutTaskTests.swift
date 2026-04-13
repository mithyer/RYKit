//
//  TimeoutTaskTests.swift
//  RYKitTests
//
//  Created by Claude on 2026/1/21.
//

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

// MARK: - OnceTimeoutTaskQueue Tests

final class OnceTimeoutTaskQueueTests: XCTestCase {
    
    enum TestError: Error {
        case failed
    }
    
    func test_addTask_executesImmediately() {
        let queue = OnceTimeoutTaskQueue<Int, TestError>(executeQueue: .global())
        let expectation = expectation(description: "task done")
        
        let task = OnceTimeoutTask<Int, TestError>(
            timeoutInterval: .seconds(10),
            execute: { $0(.success(1)) },
            done: { _ in expectation.fulfill() }
        )
        
        queue.addTask(task)
        wait(for: [expectation], timeout: 1.0)
    }
    
    func test_addTask_multiple_executesSerially() {
        let queue = OnceTimeoutTaskQueue<Int, TestError>(executeQueue: .global())
        var executionOrder: [Int] = []
        let lock = NSLock()
        let expectation = expectation(description: "all done")
        expectation.expectedFulfillmentCount = 3
        
        for i in 1...3 {
            let task = OnceTimeoutTask<Int, TestError>(
                timeoutInterval: .seconds(10),
                execute: { completed in
                    lock.lock()
                    executionOrder.append(i)
                    lock.unlock()
                    Thread.sleep(forTimeInterval: 0.05)
                    completed(.success(i))
                },
                done: { _ in expectation.fulfill() }
            )
            queue.addTask(task)
        }
        
        wait(for: [expectation], timeout: 5.0)
        XCTAssertEqual(executionOrder, [1, 2, 3])
    }
    
    func test_pause_stopsNextExecution() {
        let queue = OnceTimeoutTaskQueue<Int, TestError>(executeQueue: .global())
        var executed: [Int] = []
        let lock = NSLock()
        
        let task1Done = expectation(description: "task1")
        let task1 = OnceTimeoutTask<Int, TestError>(
            timeoutInterval: .seconds(10),
            execute: { completed in
                lock.lock()
                executed.append(1)
                lock.unlock()
                completed(.success(1))
            },
            done: { _ in task1Done.fulfill() }
        )
        
        let task2 = OnceTimeoutTask<Int, TestError>(
            timeoutInterval: .seconds(10),
            execute: { completed in
                lock.lock()
                executed.append(2)
                lock.unlock()
                completed(.success(2))
            },
            done: { _ in }
        )
        
        queue.addTask(task1)
        queue.pause()
        queue.addTask(task2)
        
        wait(for: [task1Done], timeout: 1.0)
        Thread.sleep(forTimeInterval: 0.2)
        
        // Task 2 should not have executed due to pause
        XCTAssertEqual(executed, [1])
    }
    
    func test_resume_continuesExecution() {
        let queue = OnceTimeoutTaskQueue<Int, TestError>(executeQueue: .global())
        let task2Done = expectation(description: "task2")
        
        let task1 = OnceTimeoutTask<Int, TestError>(
            timeoutInterval: .seconds(10),
            execute: { $0(.success(1)) },
            done: { _ in }
        )
        
        let task2 = OnceTimeoutTask<Int, TestError>(
            timeoutInterval: .seconds(10),
            execute: { $0(.success(2)) },
            done: { _ in task2Done.fulfill() }
        )
        
        queue.addTask(task1)
        queue.pause()
        queue.addTask(task2)
        
        Thread.sleep(forTimeInterval: 0.2)
        queue.resume()
        
        wait(for: [task2Done], timeout: 1.0)
    }
    
    func test_taskTimeout_triggersNext() {
        let queue = OnceTimeoutTaskQueue<Int, TestError>(executeQueue: .global())
        let task2Done = expectation(description: "task2")
        var task2Executed = false
        
        let task1 = OnceTimeoutTask<Int, TestError>(
            timeoutInterval: .milliseconds(100),
            execute: { _ in /* Never completes */ },
            done: { _ in }
        )
        
        let task2 = OnceTimeoutTask<Int, TestError>(
            timeoutInterval: .seconds(10),
            execute: { completed in
                task2Executed = true
                completed(.success(2))
            },
            done: { _ in task2Done.fulfill() }
        )
        
        queue.addTask(task1)
        queue.addTask(task2)
        
        wait(for: [task2Done], timeout: 2.0)
        XCTAssertTrue(task2Executed)
    }
}
