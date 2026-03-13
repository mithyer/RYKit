//
//  ThrottleCallbackTests.swift
//  RYKitTests
//
//  Created by Claude on 2026/3/13.
//

import XCTest
import Combine
@testable import RYKit

final class ThrottleCallbackTests: XCTestCase {

    // MARK: - Basic Behavior

    func test_noSend_callbackNotCalled() {
        var callCount = 0
        let _ = ThrottleCallback(interval: .seconds(1), scheduler: DispatchQueue.main) {
            callCount += 1
        }
        XCTAssertEqual(callCount, 0)
    }

    func test_firstSend_executesImmediately() {
        var callCount = 0
        let tc = ThrottleCallback(interval: .seconds(10), scheduler: DispatchQueue.main) {
            callCount += 1
        }

        tc.send()

        // .first().sink fires synchronously on PassthroughSubject
        XCTAssertEqual(callCount, 1)
    }

    func test_singleSend_executesCallbackOnce() {
        var callCount = 0
        let tc = ThrottleCallback(interval: .milliseconds(100), scheduler: DispatchQueue.main) {
            callCount += 1
        }

        tc.send()

        let exp = expectation(description: "wait past throttle interval")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            exp.fulfill()
        }
        wait(for: [exp], timeout: 1.0)

        XCTAssertEqual(callCount, 1, "Single send should only produce one callback")
    }

    // MARK: - Throttling

    func test_rapidSends_areThrottled() {
        var callCount = 0
        let tc = ThrottleCallback(interval: .milliseconds(300), scheduler: DispatchQueue.main) {
            callCount += 1
        }

        // First send - immediate via .first()
        tc.send()
        XCTAssertEqual(callCount, 1)

        // 10 rapid subsequent sends
        for _ in 0..<10 {
            tc.send()
        }

        let exp = expectation(description: "throttle interval elapsed")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            exp.fulfill()
        }
        wait(for: [exp], timeout: 1.0)

        XCTAssertLessThan(callCount, 11, "Rapid sends should be throttled, not all executed")
        XCTAssertGreaterThan(callCount, 1, "Throttled batch should eventually fire")
    }

    func test_sendsSpacedBeyondInterval_allExecute() {
        var callCount = 0
        let tc = ThrottleCallback(interval: .milliseconds(50), scheduler: DispatchQueue.main) {
            callCount += 1
        }

        tc.send() // immediate via .first()

        // Send with gaps larger than the throttle interval
        var exps: [XCTestExpectation] = []
        for i in 1...3 {
            let exp = expectation(description: "spaced send \(i)")
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(i) * 0.15) {
                tc.send()
                exp.fulfill()
            }
            exps.append(exp)
        }

        let finalExp = expectation(description: "all sends processed")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) {
            finalExp.fulfill()
        }
        exps.append(finalExp)
        wait(for: exps, timeout: 1.5)

        XCTAssertGreaterThanOrEqual(callCount, 4, "Sends spaced beyond interval should all execute")
    }

    // MARK: - Lifecycle

    func test_deinit_stopsProcessing() {
        var callCount = 0
        var tc: ThrottleCallback? = ThrottleCallback(interval: .milliseconds(50), scheduler: DispatchQueue.main) {
            callCount += 1
        }

        tc?.send()
        XCTAssertEqual(callCount, 1)

        // Release instance — cancellables deallocated
        tc = nil

        let exp = expectation(description: "wait after dealloc")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            exp.fulfill()
        }
        wait(for: [exp], timeout: 0.5)

        XCTAssertEqual(callCount, 1, "No callbacks after dealloc")
    }

    // MARK: - Custom Scheduler

    func test_worksWithCustomScheduler() {
        let queue = DispatchQueue(label: "test.throttle")
        var callCount = 0
        let lock = NSLock()

        let tc = ThrottleCallback(interval: .milliseconds(200), scheduler: queue) {
            lock.lock()
            callCount += 1
            lock.unlock()
        }

        tc.send()

        // .first() sink is synchronous even on custom scheduler
        Thread.sleep(forTimeInterval: 0.05)
        lock.lock()
        let firstCount = callCount
        lock.unlock()
        XCTAssertEqual(firstCount, 1)

        // Rapid sends
        for _ in 0..<5 {
            tc.send()
        }

        let exp = expectation(description: "throttle on custom queue")
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.4) {
            exp.fulfill()
        }
        wait(for: [exp], timeout: 1.0)

        lock.lock()
        let finalCount = callCount
        lock.unlock()
        XCTAssertGreaterThan(finalCount, 1)
        XCTAssertLessThan(finalCount, 7, "Should be throttled on custom scheduler too")
    }

    // MARK: - Burst Pattern

    func test_burstPauseBurst_throttlesEachBurst() {
        var callCount = 0
        let tc = ThrottleCallback(interval: .milliseconds(100), scheduler: DispatchQueue.main) {
            callCount += 1
        }

        // First burst
        tc.send() // immediate
        tc.send()
        tc.send()

        // Wait for throttle to settle
        let exp1 = expectation(description: "first burst settled")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
            exp1.fulfill()
        }
        wait(for: [exp1], timeout: 1.0)
        let countAfterFirstBurst = callCount

        // Second burst
        tc.send()
        tc.send()
        tc.send()

        let exp2 = expectation(description: "second burst settled")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
            exp2.fulfill()
        }
        wait(for: [exp2], timeout: 1.0)

        // Second burst should also have produced callbacks
        XCTAssertGreaterThan(callCount, countAfterFirstBurst, "Second burst should trigger additional callbacks")
    }
}
