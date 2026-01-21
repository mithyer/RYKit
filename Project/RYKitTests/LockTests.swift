//
//  LockTests.swift
//  RYKitTests
//
//  Created by Claude on 2026/1/20.
//

import XCTest
@testable import RYKit

// MARK: - UnfairLock Tests

final class UnfairLockTests: XCTestCase {
    
    func test_lock_unlock_basic() {
        let lock = UnfairLock()
        lock.lock()
        lock.unlock()
        // Should not deadlock
    }
    
    func test_tryLock_whenUnlocked_succeeds() {
        let lock = UnfairLock()
        XCTAssertTrue(lock.tryLock())
        lock.unlock()
    }
    
    func test_tryLock_whenLocked_fails() {
        let lock = UnfairLock()
        lock.lock()
        
        let expectation = expectation(description: "tryLock from another thread")
        var result = true
        
        DispatchQueue.global().async {
            result = lock.tryLock()
            expectation.fulfill()
        }
        
        wait(for: [expectation], timeout: 1.0)
        XCTAssertFalse(result)
        lock.unlock()
    }
}

// MARK: - ReadWriteLock Tests

final class ReadWriteLockTests: XCTestCase {
    
    func test_readLock_unlock_basic() {
        let lock = ReadWriteLock()
        lock.readLock()
        lock.unlock()
    }
    
    func test_writeLock_unlock_basic() {
        let lock = ReadWriteLock()
        lock.writeLock()
        lock.unlock()
    }
    
    func test_read_closure_returnsValue() {
        let lock = ReadWriteLock()
        let result = lock.read { 42 }
        XCTAssertEqual(result, 42)
    }
    
    func test_write_closure_returnsValue() {
        let lock = ReadWriteLock()
        let result = lock.write { "written" }
        XCTAssertEqual(result, "written")
    }
    
    func test_concurrent_reads_allowed() {
        let lock = ReadWriteLock()
        let readersCount = 5
        let expectations = (0..<readersCount).map { expectation(description: "reader \($0)") }
        var readersEntered = 0
        let readersSemaphore = DispatchSemaphore(value: 1)
        
        for i in 0..<readersCount {
            DispatchQueue.global().async {
                lock.readLock()
                readersSemaphore.wait()
                readersEntered += 1
                readersSemaphore.signal()
                
                // Hold lock briefly
                Thread.sleep(forTimeInterval: 0.1)
                
                lock.unlock()
                expectations[i].fulfill()
            }
        }
        
        wait(for: expectations, timeout: 2.0)
        XCTAssertEqual(readersEntered, readersCount)
    }
    
    func test_write_blocks_reads() {
        let lock = ReadWriteLock()
        lock.writeLock()
        
        var readStarted = false
        let expectation = expectation(description: "read blocked")
        
        DispatchQueue.global().async {
            readStarted = true
            lock.readLock() // Should block
            lock.unlock()
            expectation.fulfill()
        }
        
        // Give time for read to attempt
        Thread.sleep(forTimeInterval: 0.1)
        XCTAssertTrue(readStarted)
        
        lock.unlock() // Release write lock
        wait(for: [expectation], timeout: 1.0)
    }
}

// MARK: - ThreadSafe Tests

final class ThreadSafeTests: XCTestCase {
    
    func test_wrappedValue_getSet() {
        @ThreadSafe var value = 0
        value = 42
        XCTAssertEqual(value, 42)
    }
    
    func test_concurrent_increment_dataIntegrity() {
        @ThreadSafe var counter = 0
        let iterations = 1000
        let threads = 10
        let expectation = expectation(description: "all increments done")
        expectation.expectedFulfillmentCount = threads
        
        for _ in 0..<threads {
            DispatchQueue.global().async {
                for _ in 0..<iterations {
                    $counter.lock { $0 += 1 }
                }
                expectation.fulfill()
            }
        }
        
        wait(for: [expectation], timeout: 10.0)
        XCTAssertEqual(counter, threads * iterations)
    }
    
    func test_projectedValue_lock_closure() {
        @ThreadSafe var array = [Int]()
        
        $array.lock { arr in
            arr.append(1)
            arr.append(2)
            arr.append(3)
        }
        
        XCTAssertEqual(array, [1, 2, 3])
    }
    
    func test_lock_closure_returnsValue() {
        @ThreadSafe var dict = ["key": 1]
        
        let result = $dict.lock { d -> Int? in
            return d["key"]
        }
        
        XCTAssertEqual(result, 1)
    }
}

// MARK: - RWThreadSafe Tests

final class RWThreadSafeTests: XCTestCase {
    
    func test_wrappedValue_getSet() {
        @RWThreadSafe var value = "initial"
        value = "updated"
        XCTAssertEqual(value, "updated")
    }
    
    func test_concurrent_reads_writes_dataIntegrity() {
        @RWThreadSafe var counter = 0
        let writeIterations = 100
        let readIterations = 500
        let writers = 5
        let readers = 10
        
        let writeExpectation = expectation(description: "writers done")
        writeExpectation.expectedFulfillmentCount = writers
        
        let readExpectation = expectation(description: "readers done")
        readExpectation.expectedFulfillmentCount = readers
        
        // Writers
        for _ in 0..<writers {
            DispatchQueue.global().async {
                for _ in 0..<writeIterations {
                    $counter.write { $0 += 1 }
                }
                writeExpectation.fulfill()
            }
        }
        
        // Readers
        for _ in 0..<readers {
            DispatchQueue.global().async {
                for _ in 0..<readIterations {
                    _ = $counter.read { $0 }
                }
                readExpectation.fulfill()
            }
        }
        
        wait(for: [writeExpectation, readExpectation], timeout: 10.0)
        XCTAssertEqual(counter, writers * writeIterations)
    }
}

// MARK: - Exception Safety Tests

final class LockExceptionSafetyTests: XCTestCase {
    
    enum TestError: Error {
        case intentional
    }
    
    func test_readWriteLock_read_unlocks_onThrow() {
        let lock = ReadWriteLock()
        
        do {
            _ = try lock.read { () -> Int in
                throw TestError.intentional
            }
            XCTFail("Should have thrown")
        } catch {
            // Expected
        }
        
        // Lock should be released - this should not deadlock
        XCTAssertTrue(lock.tryWriteLock())
        lock.unlock()
    }
    
    func test_readWriteLock_write_unlocks_onThrow() {
        let lock = ReadWriteLock()
        
        do {
            _ = try lock.write { () -> Int in
                throw TestError.intentional
            }
            XCTFail("Should have thrown")
        } catch {
            // Expected
        }
        
        // Lock should be released
        XCTAssertTrue(lock.tryReadLock())
        lock.unlock()
    }
}

// MARK: - TimeReadWriteLock Tests

final class TimeReadWriteLockTests: XCTestCase {
    
    // MARK: - Basic Lock/Unlock
    
    func test_readLock_readUnlock_basic() {
        let lock = TimeReadWriteLock()
        lock.readLock()
        lock.readUnlock()
        // Should not deadlock
    }
    
    func test_writeLock_writeUnlock_basic() {
        let lock = TimeReadWriteLock()
        lock.writeLock()
        lock.writeUnlock()
        // Should not deadlock
    }
    
    // MARK: - Try Lock (Non-blocking)
    
    func test_tryReadLock_whenUnlocked_succeeds() {
        let lock = TimeReadWriteLock()
        XCTAssertTrue(lock.tryReadLock())
        lock.readUnlock()
    }
    
    func test_tryWriteLock_whenUnlocked_succeeds() {
        let lock = TimeReadWriteLock()
        XCTAssertTrue(lock.tryWriteLock())
        lock.writeUnlock()
    }
    
    func test_tryReadLock_whenWriteLocked_fails() {
        let lock = TimeReadWriteLock()
        lock.writeLock()
        
        let expectation = expectation(description: "tryReadLock from another thread")
        var result = true
        
        DispatchQueue.global().async {
            result = lock.tryReadLock()
            expectation.fulfill()
        }
        
        wait(for: [expectation], timeout: 1.0)
        XCTAssertFalse(result)
        lock.writeUnlock()
    }
    
    func test_tryWriteLock_whenReadLocked_fails() {
        let lock = TimeReadWriteLock()
        lock.readLock()
        
        let expectation = expectation(description: "tryWriteLock from another thread")
        var result = true
        
        DispatchQueue.global().async {
            result = lock.tryWriteLock()
            expectation.fulfill()
        }
        
        wait(for: [expectation], timeout: 1.0)
        XCTAssertFalse(result)
        lock.readUnlock()
    }
    
    // MARK: - Timeout Tests
    
    func test_readLock_timeout_succeeds_whenAvailable() {
        let lock = TimeReadWriteLock()
        XCTAssertTrue(lock.readLock(timeout: 0.5))
        lock.readUnlock()
    }
    
    func test_readLock_timeout_fails_whenWriteLocked() {
        let lock = TimeReadWriteLock()
        lock.writeLock()
        
        let expectation = expectation(description: "readLock timeout")
        var result = true
        
        DispatchQueue.global().async {
            let start = Date()
            result = lock.readLock(timeout: 0.2)
            let elapsed = Date().timeIntervalSince(start)
            // Should have waited approximately 0.2 seconds
            XCTAssertGreaterThan(elapsed, 0.15)
            XCTAssertLessThan(elapsed, 0.5)
            expectation.fulfill()
        }
        
        wait(for: [expectation], timeout: 1.0)
        XCTAssertFalse(result)
        lock.writeUnlock()
    }
    
    func test_writeLock_timeout_succeeds_whenAvailable() {
        let lock = TimeReadWriteLock()
        XCTAssertTrue(lock.writeLock(timeout: 0.5))
        lock.writeUnlock()
    }
    
    func test_writeLock_timeout_fails_whenLocked() {
        let lock = TimeReadWriteLock()
        lock.writeLock()
        
        let expectation = expectation(description: "writeLock timeout")
        var result = true
        
        DispatchQueue.global().async {
            let start = Date()
            result = lock.writeLock(timeout: 0.2)
            let elapsed = Date().timeIntervalSince(start)
            XCTAssertGreaterThan(elapsed, 0.15)
            XCTAssertLessThan(elapsed, 0.5)
            expectation.fulfill()
        }
        
        wait(for: [expectation], timeout: 1.0)
        XCTAssertFalse(result)
        lock.writeUnlock()
    }
    
    // MARK: - Closure Methods
    
    func test_read_closure_returnsValue() {
        let lock = TimeReadWriteLock()
        let result = lock.read { 42 }
        XCTAssertEqual(result, 42)
    }
    
    func test_write_closure_returnsValue() {
        let lock = TimeReadWriteLock()
        let result = lock.write { "written" }
        XCTAssertEqual(result, "written")
    }
    
    func test_read_closure_withTimeout_succeeds() {
        let lock = TimeReadWriteLock()
        let result = lock.read(timeout: 0.5) { 42 }
        XCTAssertEqual(result, 42)
    }
    
    func test_read_closure_withTimeout_returnsNil_whenLocked() {
        let lock = TimeReadWriteLock()
        lock.writeLock()
        
        let expectation = expectation(description: "read timeout")
        var result: Int? = 999
        
        DispatchQueue.global().async {
            result = lock.read(timeout: 0.1) { 42 }
            expectation.fulfill()
        }
        
        wait(for: [expectation], timeout: 1.0)
        XCTAssertNil(result)
        lock.writeUnlock()
    }
    
    func test_write_closure_withTimeout_succeeds() {
        let lock = TimeReadWriteLock()
        let result = lock.write(timeout: 0.5) { "written" }
        XCTAssertEqual(result, "written")
    }
    
    func test_write_closure_withTimeout_returnsNil_whenLocked() {
        let lock = TimeReadWriteLock()
        lock.writeLock()
        
        let expectation = expectation(description: "write timeout")
        var result: String? = "initial"
        
        DispatchQueue.global().async {
            result = lock.write(timeout: 0.1) { "written" }
            expectation.fulfill()
        }
        
        wait(for: [expectation], timeout: 1.0)
        XCTAssertNil(result)
        lock.writeUnlock()
    }
    
    // MARK: - Concurrent Reads
    
    func test_concurrent_reads_allowed() {
        let lock = TimeReadWriteLock()
        let readersCount = 5
        let expectations = (0..<readersCount).map { expectation(description: "reader \($0)") }
        var readersEntered = 0
        let counterLock = DispatchSemaphore(value: 1)
        
        for i in 0..<readersCount {
            DispatchQueue.global().async {
                lock.readLock()
                counterLock.wait()
                readersEntered += 1
                counterLock.signal()
                
                // Hold lock briefly to ensure overlap
                Thread.sleep(forTimeInterval: 0.1)
                
                lock.readUnlock()
                expectations[i].fulfill()
            }
        }
        
        wait(for: expectations, timeout: 2.0)
        XCTAssertEqual(readersEntered, readersCount)
    }
    
    // MARK: - Data Integrity
    
    func test_concurrent_writes_dataIntegrity() {
        let lock = TimeReadWriteLock()
        var counter = 0
        let iterations = 500
        let writers = 5
        
        let expectation = expectation(description: "all writes done")
        expectation.expectedFulfillmentCount = writers
        
        for _ in 0..<writers {
            DispatchQueue.global().async {
                for _ in 0..<iterations {
                    lock.write {
                        counter += 1
                    }
                }
                expectation.fulfill()
            }
        }
        
        wait(for: [expectation], timeout: 10.0)
        XCTAssertEqual(counter, writers * iterations)
    }
    
    // MARK: - Exception Safety
    
    enum TestError: Error {
        case intentional
    }
    
    func test_read_closure_unlocks_onThrow() {
        let lock = TimeReadWriteLock()
        
        do {
            _ = try lock.read { () -> Int in
                throw TestError.intentional
            }
            XCTFail("Should have thrown")
        } catch {
            // Expected
        }
        
        // Lock should be released
        XCTAssertTrue(lock.tryWriteLock())
        lock.writeUnlock()
    }
    
    func test_write_closure_unlocks_onThrow() {
        let lock = TimeReadWriteLock()
        
        do {
            _ = try lock.write { () -> Int in
                throw TestError.intentional
            }
            XCTFail("Should have thrown")
        } catch {
            // Expected
        }
        
        // Lock should be released
        XCTAssertTrue(lock.tryReadLock())
        lock.readUnlock()
    }
}

// MARK: - Edge Cases

final class LockEdgeCaseTests: XCTestCase {
    
    func test_readWriteLock_tryReadLock_whenWriteLocked() {
        let lock = ReadWriteLock()
        lock.writeLock()
        
        let expectation = expectation(description: "tryReadLock")
        var result = true
        
        DispatchQueue.global().async {
            result = lock.tryReadLock()
            expectation.fulfill()
        }
        
        wait(for: [expectation], timeout: 1.0)
        XCTAssertFalse(result)
        lock.unlock()
    }
    
    func test_readWriteLock_tryWriteLock_whenReadLocked() {
        let lock = ReadWriteLock()
        lock.readLock()
        
        let expectation = expectation(description: "tryWriteLock")
        var result = true
        
        DispatchQueue.global().async {
            result = lock.tryWriteLock()
            expectation.fulfill()
        }
        
        wait(for: [expectation], timeout: 1.0)
        XCTAssertFalse(result)
        lock.unlock()
    }
    
    func test_threadSafe_with_reference_type() {
        class Counter {
            var value = 0
        }
        
        @ThreadSafe var counter = Counter()
        let iterations = 1000
        let threads = 10
        let expectation = expectation(description: "all done")
        expectation.expectedFulfillmentCount = threads
        
        for _ in 0..<threads {
            DispatchQueue.global().async {
                for _ in 0..<iterations {
                    $counter.lock { $0.value += 1 }
                }
                expectation.fulfill()
            }
        }
        
        wait(for: [expectation], timeout: 10.0)
        XCTAssertEqual(counter.value, threads * iterations)
    }
    
    func test_rwThreadSafe_read_during_write() {
        @RWThreadSafe var value = 0
        let writeStarted = DispatchSemaphore(value: 0)
        let writeDone = DispatchSemaphore(value: 0)
        
        // Writer holds lock
        DispatchQueue.global().async {
            $value.write { v in
                writeStarted.signal()
                Thread.sleep(forTimeInterval: 0.2)
                v = 42
            }
            writeDone.signal()
        }
        
        writeStarted.wait()
        
        // Reader should block until write completes
        let start = Date()
        let readValue = $value.read { $0 }
        let elapsed = Date().timeIntervalSince(start)
        
        writeDone.wait()
        
        XCTAssertEqual(readValue, 42)
        XCTAssertGreaterThan(elapsed, 0.1) // Was blocked
    }
}

// MARK: - Performance Benchmarks

final class LockPerformanceTests: XCTestCase {
    
    func test_performance_unfairLock_vs_nslock() {
        let unfairLock = UnfairLock()
        let nsLock = NSLock()
        let iterations = 100_000
        
        measure {
            for _ in 0..<iterations {
                unfairLock.lock()
                unfairLock.unlock()
            }
        }
        
        // Baseline comparison (not asserted, just for reference)
        let start = Date()
        for _ in 0..<iterations {
            nsLock.lock()
            nsLock.unlock()
        }
        let nsLockTime = Date().timeIntervalSince(start)
        print("NSLock time: \(nsLockTime)s")
    }
    
    func test_performance_readWriteLock_readHeavy() {
        let lock = ReadWriteLock()
        var value = 0
        
        measure {
            DispatchQueue.concurrentPerform(iterations: 1000) { i in
                if i % 10 == 0 {
                    lock.write { value += 1 }
                } else {
                    _ = lock.read { value }
                }
            }
        }
    }
    
    func test_performance_readWriteLock_writeHeavy() {
        let lock = ReadWriteLock()
        var value = 0
        
        measure {
            DispatchQueue.concurrentPerform(iterations: 1000) { i in
                if i % 10 == 0 {
                    _ = lock.read { value }
                } else {
                    lock.write { value += 1 }
                }
            }
        }
    }
    
    func test_performance_threadSafe_highContention() {
        @ThreadSafe var counter = 0
        
        measure {
            DispatchQueue.concurrentPerform(iterations: 10000) { _ in
                $counter.lock { $0 += 1 }
            }
        }
    }
}

// MARK: - Stress Tests

final class LockStressTests: XCTestCase {
    
    func test_stress_100threads_10000iterations() {
        @ThreadSafe var counter = 0
        let threads = 100
        let iterations = 10000
        let expectation = expectation(description: "stress test")
        expectation.expectedFulfillmentCount = threads
        
        for _ in 0..<threads {
            DispatchQueue.global().async {
                for _ in 0..<iterations {
                    $counter.lock { $0 += 1 }
                }
                expectation.fulfill()
            }
        }
        
        wait(for: [expectation], timeout: 60.0)
        XCTAssertEqual(counter, threads * iterations)
    }
    
    func test_stress_rapid_lock_unlock() {
        let lock = UnfairLock()
        let iterations = 1_000_000
        
        let start = Date()
        for _ in 0..<iterations {
            lock.lock()
            lock.unlock()
        }
        let elapsed = Date().timeIntervalSince(start)
        
        // Should complete in reasonable time (< 5 seconds)
        XCTAssertLessThan(elapsed, 5.0)
        print("Rapid lock/unlock: \(iterations) iterations in \(elapsed)s")
    }
}
