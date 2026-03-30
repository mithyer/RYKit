import XCTest
import Combine
@testable import RYKit

final class DebounceCallbackTests: XCTestCase {

    func test_singleSend_executesOnlyAfterDebounceInterval() {
        var callCount = 0
        let callback = DebounceCallback(interval: .milliseconds(100))

        callback.send { callCount += 1 }

        XCTAssertEqual(callCount, 0, "Single send should not execute immediately in debounce mode")

        let exp = expectation(description: "debounce interval elapsed")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            exp.fulfill()
        }
        wait(for: [exp], timeout: 1.0)

        XCTAssertEqual(callCount, 1, "Single send should execute once after debounce interval")
    }

    func test_rapidSends_executeOnlyLatestClosureInDefaultMode() {
        var received: [String] = []
        let callback = DebounceCallback(interval: .milliseconds(120))

        callback.send { received.append("A") }
        callback.send { received.append("B") }
        callback.send { received.append("C") }

        XCTAssertTrue(received.isEmpty, "Debounce should suppress immediate execution")

        let exp = expectation(description: "debounce latest closure fired")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
            exp.fulfill()
        }
        wait(for: [exp], timeout: 1.0)

        XCTAssertEqual(received, ["C"], "Only the latest closure should run after the debounce interval")
    }

    func test_firstSend_executesImmediatelyWhenEnabled() {
        var callCount = 0
        let callback = DebounceCallback(
            interval: .seconds(10),
            shouldPerformFirstImmediately: true
        )

        callback.send { callCount += 1 }

        XCTAssertEqual(callCount, 1, "First send should execute immediately when leading behavior is enabled")
    }

    func test_singleSend_doesNotExecuteTwiceWhenLeadingEnabled() {
        var callCount = 0
        let callback = DebounceCallback(
            interval: .milliseconds(100),
            shouldPerformFirstImmediately: true
        )

        callback.send { callCount += 1 }
        XCTAssertEqual(callCount, 1)

        let exp = expectation(description: "wait past debounce interval")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            exp.fulfill()
        }
        wait(for: [exp], timeout: 1.0)

        XCTAssertEqual(callCount, 1, "Single send should not be replayed by trailing debounce")
    }

    func test_subsequentRapidSends_debounceToLatestWhenLeadingEnabled() {
        var received: [String] = []
        let callback = DebounceCallback(
            interval: .milliseconds(120),
            shouldPerformFirstImmediately: true
        )

        callback.send { received.append("A") }
        XCTAssertEqual(received, ["A"])

        callback.send { received.append("B") }
        callback.send { received.append("C") }
        callback.send { received.append("D") }

        let exp = expectation(description: "leading mode trailing debounce settled")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
            exp.fulfill()
        }
        wait(for: [exp], timeout: 1.0)

        XCTAssertEqual(received, ["A", "D"], "Leading mode should execute the first closure immediately and the latest later closure after debounce")
    }

    func test_deinit_stopsPendingDebouncedExecution() {
        var callCount = 0
        var callback: DebounceCallback? = DebounceCallback(interval: .milliseconds(100))

        callback?.send { callCount += 1 }
        callback = nil

        let exp = expectation(description: "wait after dealloc")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            exp.fulfill()
        }
        wait(for: [exp], timeout: 1.0)

        XCTAssertEqual(callCount, 0, "Pending debounced work should not fire after instance deallocation")
    }

    func test_defaultMode_worksWithCustomScheduler() {
        let queue = DispatchQueue(label: "test.debounce")
        let lock = NSLock()
        var callCount = 0
        let callback = DebounceCallback(interval: .milliseconds(80), scheduler: queue)

        callback.send {
            lock.lock()
            callCount += 1
            lock.unlock()
        }

        Thread.sleep(forTimeInterval: 0.03)
        lock.lock()
        let earlyCount = callCount
        lock.unlock()
        XCTAssertEqual(earlyCount, 0, "Default debounce mode should not execute immediately on custom scheduler")

        let exp = expectation(description: "custom scheduler debounce settled")
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.2) {
            exp.fulfill()
        }
        wait(for: [exp], timeout: 1.0)

        lock.lock()
        let finalCount = callCount
        lock.unlock()
        XCTAssertEqual(finalCount, 1, "Debounced closure should eventually execute on custom scheduler")
    }
}
