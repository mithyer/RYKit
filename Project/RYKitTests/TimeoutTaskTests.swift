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
    
    func test_init_state_isUnstart() {
        let task = OnceTimeoutTask<Int, TestError>(
            timeoutInterval: .seconds(1),
            execute: { _ in },
            done: { _ in }
        )
        XCTAssertFalse(task.state.hasStarted)
        XCTAssertFalse(task.state.isDone)
    }
    
    func test_perform_state_becomesExecuting() {
        let task = OnceTimeoutTask<Int, TestError>(
            timeoutInterval: .seconds(10),
            execute: { _ in },
            done: { _ in }
        )
        
        task.perform(by: .global(), timeoutQueue: .global())
        
        // Give time for async execution
        Thread.sleep(forTimeInterval: 0.1)
        XCTAssertTrue(task.state.hasStarted)
    }
    
    func test_complete_success_callsDone() {
        let expectation = expectation(description: "done called")
        var doneType: OnceTimeoutTask<Int, TestError>.DoneType?
        
        let task = OnceTimeoutTask<Int, TestError>(
            timeoutInterval: .seconds(10),
            execute: { completed in
                completed(.success(42))
            },
            done: { type in
                doneType = type
                expectation.fulfill()
            }
        )
        
        task.perform(by: .global(), timeoutQueue: .global())
        wait(for: [expectation], timeout: 1.0)
        
        if case .completed(let result) = doneType {
            XCTAssertEqual(try? result.get(), 42)
        } else {
            XCTFail("Expected completed, got \(String(describing: doneType))")
        }
        XCTAssertTrue(task.state.isDone)
    }
    
    func test_complete_failure_callsDone() {
        let expectation = expectation(description: "done called")
        var doneType: OnceTimeoutTask<Int, TestError>.DoneType?
        
        let task = OnceTimeoutTask<Int, TestError>(
            timeoutInterval: .seconds(10),
            execute: { completed in
                completed(.failure(.failed))
            },
            done: { type in
                doneType = type
                expectation.fulfill()
            }
        )
        
        task.perform(by: .global(), timeoutQueue: .global())
        wait(for: [expectation], timeout: 1.0)
        
        if case .completed(let result) = doneType {
            XCTAssertThrowsError(try result.get())
        } else {
            XCTFail("Expected completed with error")
        }
    }
    
    func test_timeout_callsDoneWithTimeout() {
        let expectation = expectation(description: "timeout")
        var doneType: OnceTimeoutTask<Int, TestError>.DoneType?
        
        let task = OnceTimeoutTask<Int, TestError>(
            timeoutInterval: .milliseconds(100),
            execute: { _ in
                // Never completes
            },
            done: { type in
                doneType = type
                expectation.fulfill()
            }
        )
        
        task.perform(by: .global(), timeoutQueue: .global())
        wait(for: [expectation], timeout: 1.0)
        
        if case .timeout = doneType {
            // Success
        } else {
            XCTFail("Expected timeout, got \(String(describing: doneType))")
        }
        XCTAssertTrue(task.state.isDone)
    }
    
    func test_complete_beforeTimeout_cancelsTimeout() {
        let doneExpectation = expectation(description: "done")
        var callCount = 0
        
        let task = OnceTimeoutTask<Int, TestError>(
            timeoutInterval: .milliseconds(200),
            execute: { completed in
                // Complete immediately
                completed(.success(1))
            },
            done: { _ in
                callCount += 1
                doneExpectation.fulfill()
            }
        )
        
        task.perform(by: .global(), timeoutQueue: .global())
        wait(for: [doneExpectation], timeout: 1.0)
        
        // Wait past timeout to ensure it doesn't fire
        Thread.sleep(forTimeInterval: 0.3)
        XCTAssertEqual(callCount, 1, "Done should only be called once")
    }
    
    func test_perform_twice_secondIgnored() {
        var executeCount = 0
        let expectation = expectation(description: "done")
        
        let task = OnceTimeoutTask<Int, TestError>(
            timeoutInterval: .seconds(10),
            execute: { completed in
                executeCount += 1
                completed(.success(1))
            },
            done: { _ in
                expectation.fulfill()
            }
        )
        
        task.perform(by: .global(), timeoutQueue: .global())
        task.perform(by: .global(), timeoutQueue: .global()) // Second call
        
        wait(for: [expectation], timeout: 1.0)
        XCTAssertEqual(executeCount, 1)
    }
    
    func test_complete_afterDone_ignored() {
        let expectation = expectation(description: "done")
        var callCount = 0
        var capturedComplete: ((Result<Int, TestError>) -> Void)?
        
        let task = OnceTimeoutTask<Int, TestError>(
            timeoutInterval: .seconds(10),
            execute: { completed in
                capturedComplete = completed
                completed(.success(1))
            },
            done: { _ in
                callCount += 1
                expectation.fulfill()
            }
        )
        
        task.perform(by: .global(), timeoutQueue: .global())
        wait(for: [expectation], timeout: 1.0)
        
        // Try to complete again
        capturedComplete?(.success(2))
        Thread.sleep(forTimeInterval: 0.1)
        
        XCTAssertEqual(callCount, 1)
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
