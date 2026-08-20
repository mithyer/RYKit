//
//  LogTests.swift
//  RYKitTests
//

import XCTest
#if SWIFT_PACKAGE
@testable import RYKitCore
#else
// Keep logging calls unqualified: this Xcode target compiles Classes directly and also links RYKit.framework.
@testable import RYKit
#endif

/// A single log captured from the LoggerProtocol seam.
private struct CapturedLog {
    /// The message evaluated by the logger adapter.
    let message: String
    /// The formatted log type, including its associated key.
    let typeDescription: String
    /// The interval passed to the logger adapter.
    let minIntervalBetweenSameKey: TimeInterval?
    /// The source file passed to the logger adapter.
    let file: String
    /// The source line passed to the logger adapter.
    let line: Int
    /// The source function passed to the logger adapter.
    let function: String
}

/// A CustomStringConvertible value that records when its description is evaluated.
private final class DescriptionCounter: CustomStringConvertible {
    /// Protects the evaluation count when a test invokes the value concurrently.
    private let lock = NSLock()
    /// The number of times `description` has been evaluated.
    private(set) var evaluationCount = 0

    /// Returns a stable message and records the evaluation.
    var description: String {
        lock.lock()
        evaluationCount += 1
        lock.unlock()
        return "counted-message"
    }
}

/// A thread-safe logger adapter used to observe the public logging seam.
private enum CapturingLogger: LoggerProtocol {
    /// Protects the captured entries from concurrent test calls.
    private static let lock = NSLock()
    /// Entries forwarded through LoggerProtocol.log_plain.
    private static var capturedEntries: [CapturedLog] = []

    /// Clears entries captured by previous test cases.
    static func reset() {
        lock.lock()
        capturedEntries.removeAll()
        lock.unlock()
    }

    /// Returns a snapshot of all entries captured so far.
    static func entries() -> [CapturedLog] {
        lock.lock()
        let snapshot = capturedEntries
        lock.unlock()
        return snapshot
    }

    /// Captures the deferred message and all logger metadata.
    /// - Parameters:
    ///   - str: The deferred message supplied by the logging API.
    ///   - type: The log type and associated interval key.
    ///   - minIntervalBetweenSameKey: The optional interval-throttling value.
    ///   - file: The source file supplied by the caller.
    ///   - line: The source line supplied by the caller.
    ///   - function: The source function supplied by the caller.
    static func log_plain(
        _ str: @escaping @autoclosure () -> String,
        type: LogType,
        minIntervalBetweenSameKey: TimeInterval?,
        file: StaticString,
        line: Int,
        function: StaticString
    ) {
        let entry = CapturedLog(
            message: str(),
            typeDescription: type.description,
            minIntervalBetweenSameKey: minIntervalBetweenSameKey,
            file: String(describing: file),
            line: line,
            function: String(describing: function)
        )

        lock.lock()
        capturedEntries.append(entry)
        lock.unlock()
    }
}

/// Returns the threshold selected by the active compilation configuration.
private var compiledDefaultLogLevel: LogLevel {
#if DEBUG
    return LogLevel.debug
#else
    return LogLevel.error
#endif
}

/// Tests the public log level filtering and compatibility wrappers.
final class LogTests: XCTestCase {

    /// Installs the capturing adapter and resets process-wide logging state.
    override func setUp() {
        super.setUp()
        setActiveLogger(CapturingLogger.self)
        CapturingLogger.reset()
        setLogLevel(compiledDefaultLogLevel)
    }

    /// Restores the default logger and threshold after each test.
    override func tearDown() {
        setActiveLogger(DefaultLogger.self)
        setLogLevel(compiledDefaultLogLevel)
        CapturingLogger.reset()
        super.tearDown()
    }

    /// Verifies the public level order and Comparable implementation.
    /// TEST:Log.swift[LogLevel]
    func test_logLevel_allCasesFollowSeverityOrder() {
        XCTAssertEqual(LogLevel.allCases, [LogLevel.verbose, LogLevel.debug, LogLevel.info, LogLevel.warn, LogLevel.error])
        XCTAssertEqual(LogLevel.verbose.rawValue, 0)
        XCTAssertTrue(LogLevel.verbose < LogLevel.debug)
        XCTAssertTrue(LogLevel.debug < LogLevel.info)
        XCTAssertTrue(LogLevel.info < LogLevel.warn)
        XCTAssertTrue(LogLevel.warn < LogLevel.error)
    }

    /// Verifies the compile-time default threshold for the active build.
    /// TEST:Log.swift[configuredLogLevel]
    func test_defaultLogLevel_matchesBuildConfiguration() {
        let levels: [LogLevel] = [LogLevel.verbose, LogLevel.debug, LogLevel.info, LogLevel.warn, LogLevel.error]
        for (index, level) in levels.enumerated() {
            log("message-\(index)", level: level, key: "key-\(index)")
        }

        let descriptions = CapturingLogger.entries().map(\.typeDescription)
#if DEBUG
        XCTAssertEqual(descriptions, ["[#DEBUG#]key-1", "[#INFO#]key-2", "[#WARN#]key-3", "[#ERROR#]key-4"])
#else
        XCTAssertEqual(descriptions, ["[#ERROR#]key-4"])
#endif
    }

    /// Verifies that the lowest explicit threshold forwards every level.
    /// TEST:Log.swift[log]
    func test_verboseThreshold_forwardsAllLevels() {
        setLogLevel(LogLevel.verbose)
        let levels: [LogLevel] = [LogLevel.verbose, LogLevel.debug, LogLevel.info, LogLevel.warn, LogLevel.error]

        for (index, level) in levels.enumerated() {
            log("message-\(index)", level: level, key: "key-\(index)")
        }

        XCTAssertEqual(
            CapturingLogger.entries().map(\.typeDescription),
            ["[#VERBOSE#]key-0", "[#DEBUG#]key-1", "[#INFO#]key-2", "[#WARN#]key-3", "[#ERROR#]key-4"]
        )
    }

    /// Verifies that debug filtering excludes only verbose messages.
    /// TEST:Log.swift[log]
    func test_debugThreshold_filtersOnlyVerbose() {
        setLogLevel(LogLevel.debug)
        log("verbose", level: LogLevel.verbose, key: "verbose")
        log("debug", level: LogLevel.debug, key: "debug")
        log("info", level: LogLevel.info, key: "info")
        log("warn", level: LogLevel.warn, key: "warn")
        log("error", level: LogLevel.error, key: "error")

        XCTAssertEqual(
            CapturingLogger.entries().map(\.typeDescription),
            ["[#DEBUG#]debug", "[#INFO#]info", "[#WARN#]warn", "[#ERROR#]error"]
        )
    }

    /// Verifies that an error threshold forwards only errors.
    /// TEST:Log.swift[log]
    func test_errorThreshold_forwardsOnlyErrors() {
        setLogLevel(LogLevel.error)
        log("verbose", level: LogLevel.verbose, key: "verbose")
        log("debug", level: LogLevel.debug, key: "debug")
        log("info", level: LogLevel.info, key: "info")
        log("warn", level: LogLevel.warn, key: "warn")
        log("error", level: LogLevel.error, key: "error")

        XCTAssertEqual(CapturingLogger.entries().map(\.typeDescription), ["[#ERROR#]error"])
    }

    /// Verifies that changing the threshold affects subsequent calls.
    /// TEST:Log.swift[setLogLevel]
    func test_setLogLevel_appliesToSubsequentCalls() {
        setLogLevel(LogLevel.error)
        log("filtered", level: LogLevel.warn, key: "filtered")

        setLogLevel(LogLevel.warn)
        log("warn", level: LogLevel.warn, key: "warn")

        setLogLevel(LogLevel.verbose)
        log("debug", level: LogLevel.debug, key: "debug")

        XCTAssertEqual(CapturingLogger.entries().map(\.typeDescription), ["[#WARN#]warn", "[#DEBUG#]debug"])
    }

    /// Verifies that filtering avoids evaluating the common entry point's autoclosure.
    /// TEST:Log.swift[log]
    func test_filteredLog_doesNotEvaluateMessage() {
        setLogLevel(LogLevel.error)
        let counter = DescriptionCounter()

        log(counter, level: LogLevel.debug, key: "filtered")
        XCTAssertEqual(counter.evaluationCount, 0)

        setLogLevel(LogLevel.debug)
        log(counter, level: LogLevel.debug, key: "accepted")
        XCTAssertEqual(counter.evaluationCount, 1)
    }

    /// Verifies that compatibility wrappers also filter before evaluating messages.
    /// TEST:Log.swift[log_info,log_warn,log_err]
    func test_filteredCompatibilityWrappers_doNotEvaluateMessage() {
        setLogLevel(LogLevel.error)
        let counter = DescriptionCounter()

        log_info(counter, infoKey: "info")
        log_warn(counter, warnKey: "warn")
        XCTAssertEqual(counter.evaluationCount, 0)

        log_err(counter, errKey: "error")
        XCTAssertEqual(counter.evaluationCount, 1)
        XCTAssertEqual(CapturingLogger.entries().map(\.typeDescription), ["[#ERROR#]error"])
    }

    /// Verifies level, key, interval, and source metadata forwarding.
    /// TEST:Log.swift[log_info,log_warn,log_err]
    func test_compatibilityWrappers_forwardKeyAndMetadata() {
        setLogLevel(LogLevel.verbose)
        log_info("info", infoKey: "info-key", minIntervalBetweenSameKey: 1.5, file: "test-file", line: 41, function: "testFunction")
        log_warn("warn", warnKey: "warn-key", minIntervalBetweenSameKey: 2.5, file: "test-file", line: 42, function: "testFunction")
        log_err("error", errKey: "error-key", minIntervalBetweenSameKey: 3.5, file: "test-file", line: 43, function: "testFunction")

        let entries = CapturingLogger.entries()
        XCTAssertEqual(entries.map(\.typeDescription), ["[#INFO#]info-key", "[#WARN#]warn-key", "[#ERROR#]error-key"])
        XCTAssertEqual(entries.map(\.minIntervalBetweenSameKey), [1.5, 2.5, 3.5])
        XCTAssertEqual(entries.map(\.file), ["test-file", "test-file", "test-file"])
        XCTAssertEqual(entries.map(\.line), [41, 42, 43])
        XCTAssertEqual(entries.map(\.function), ["testFunction", "testFunction", "testFunction"])

        let expectedDefaultLine = #line + 1
        log_info("default", infoKey: "default-key")
        guard let defaultEntry = CapturingLogger.entries().last else {
            return XCTFail("Expected a captured default-metadata entry")
        }
        XCTAssertEqual(defaultEntry.typeDescription, "[#INFO#]default-key")
        XCTAssertEqual(defaultEntry.message, "default")
        XCTAssertTrue(defaultEntry.file.contains("LogTests.swift"))
        XCTAssertEqual(defaultEntry.line, expectedDefaultLine)
        XCTAssertTrue(defaultEntry.function.contains("test_compatibilityWrappers_forwardKeyAndMetadata"))
    }

    /// Verifies the labels and associated keys for every public log type.
    /// TEST:Log.swift[LogType.description]
    func test_logTypeDescriptions_includeAllLevelsAndKeys() {
        XCTAssertEqual(LogType.verbose("verbose-key").description, "[#VERBOSE#]verbose-key")
        XCTAssertEqual(LogType.debug("debug-key").description, "[#DEBUG#]debug-key")
        XCTAssertEqual(LogType.info("info-key").description, "[#INFO#]info-key")
        XCTAssertEqual(LogType.warn("warn-key").description, "[#WARN#]warn-key")
        XCTAssertEqual(LogType.error("error-key").description, "[#ERROR#]error-key")
        XCTAssertEqual(LogType.error(nil).description, "[#ERROR#]")
    }

    /// Verifies that concurrent threshold changes complete without a data race in the level state.
    /// TEST:Log.swift[setLogLevel,setActiveLogger,log]
    func test_concurrentLevelChanges_completeSafely() {
        DispatchQueue.concurrentPerform(iterations: 100) { index in
            setActiveLogger(CapturingLogger.self)
            setLogLevel(index.isMultiple(of: 2) ? LogLevel.debug : LogLevel.error)
            log("message-\(index)", level: LogLevel.info, key: "key-\(index)")
        }

        let entries = CapturingLogger.entries()
        XCTAssertLessThanOrEqual(entries.count, 100)
        XCTAssertTrue(entries.allSatisfy { $0.typeDescription.hasPrefix("[#INFO#]") })

        setLogLevel(LogLevel.info)
        log("post-concurrency", level: LogLevel.info, key: "post-concurrency")
        XCTAssertTrue(CapturingLogger.entries().contains { $0.message == "post-concurrency" })
    }

#if !DEBUG
    /// Verifies that Release DefaultLogger forwards an eligible error to its recorder.
    /// TEST:Log.swift[DefaultLogger.log_plain]
    func test_releaseDefaultLogger_forwardsError() throws {
        let marker = "release-error-\(UUID().uuidString)"
        setActiveLogger(DefaultLogger.self)
        log(marker, level: LogLevel.error, key: marker)
        DefaultLogger.recorder.flush()

        let path = try XCTUnwrap(DefaultLogger.recorder.getCurrentLogFilePath())
        let contents = try String(contentsOf: URL(fileURLWithPath: path), encoding: .utf8)
        XCTAssertTrue(contents.contains(marker))
    }
#endif
}
