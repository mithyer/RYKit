//
//  Log.swift
//  RYKit
//
//  Created by ray on 2025/12/9.
//

import Foundation

/// Receives log messages after the global level filter has accepted them.
public protocol LoggerProtocol {
    /// Records a deferred plain-text log message.
    /// - Parameters:
    ///   - str: The message evaluated by the logger implementation.
    ///   - type: The log level and optional interval-throttling key.
    ///   - minIntervalBetweenSameKey: The minimum interval for the associated key.
    ///   - file: The source file that emitted the log.
    ///   - line: The source line that emitted the log.
    ///   - function: The source function that emitted the log.
    static func log_plain(
        _ str: @escaping @autoclosure () -> String,
        type: LogType,
        minIntervalBetweenSameKey: TimeInterval?,
        file: StaticString,
        line: Int,
        function: StaticString
    )
}

/// The default logger that persists accepted messages through LogRecorder.
struct DefaultLogger: LoggerProtocol {
    /// The process-wide recorder used by the default logger.
    static let recorder = LogRecorder(logNamePrefix: "default")

    /// Forwards an accepted message to the recorder while retaining deferred evaluation.
    /// - Parameters:
    ///   - str: The deferred message supplied by the global logging API.
    ///   - type: The log level and optional interval-throttling key.
    ///   - minIntervalBetweenSameKey: The minimum interval for the associated key.
    ///   - file: The source file that emitted the log.
    ///   - line: The source line that emitted the log.
    ///   - function: The source function that emitted the log.
    /// TEST:LogTests[test_releaseDefaultLogger_forwardsError]
    static func log_plain(
        _ str: @escaping @autoclosure () -> String,
        type: LogType,
        minIntervalBetweenSameKey: TimeInterval?,
        file: StaticString,
        line: Int,
        function: StaticString
    ) {
        recorder.printAndSaveLog(
            content: str(),
            style: .plainText,
            key: "\(type)",
            minIntervalBetweenSameKey: minIntervalBetweenSameKey,
            file: file,
            line: line,
            function: function
        )
    }
}

/// The logger type used by the process-wide logging entry points.
private var activeLogger: LoggerProtocol.Type = DefaultLogger.self
/// Serializes access to the process-wide logger adapter.
private let activeLoggerLock = NSLock()

/// Replaces the process-wide logger adapter.
/// - Parameter logger: The logger type that receives accepted messages.
/// TEST:LogTests[test_concurrentLevelChanges_completeSafely]
public func setActiveLogger(_ logger: LoggerProtocol.Type) {
    activeLoggerLock.lock()
    activeLogger = logger
    activeLoggerLock.unlock()
}

/// Reads the process-wide logger adapter while holding its lock.
private func currentLogger() -> LoggerProtocol.Type {
    activeLoggerLock.lock()
    let logger = activeLogger
    activeLoggerLock.unlock()
    return logger
}

/// The ordered severity levels supported by the global logging API.
/// TEST:LogTests[test_logLevel_allCasesFollowSeverityOrder]
public enum LogLevel: Int, Comparable, CaseIterable {
    /// The most detailed logging level.
    case verbose = 0
    /// Diagnostic information useful during development.
    case debug
    /// Normal informational messages.
    case info
    /// Potentially problematic but recoverable conditions.
    case warn
    /// Highest-severity failures.
    case error

    /// Compares levels by their declared severity order.
    public static func < (lhs: Self, rhs: Self) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

/// Serializes access to the process-wide configured threshold.
private let logLevelLock = NSLock()
#if DEBUG
/// The minimum level used by DEBUG builds.
/// TEST:LogTests[test_defaultLogLevel_matchesBuildConfiguration]
private var configuredLogLevel: LogLevel = .debug
#else
/// The minimum level used by non-DEBUG builds.
/// TEST:LogTests[test_defaultLogLevel_matchesBuildConfiguration]
private var configuredLogLevel: LogLevel = .error
#endif

/// Changes the process-wide minimum level required for a message to be emitted.
/// - Parameter level: The lowest severity level that should be forwarded.
/// TEST:LogTests[test_setLogLevel_appliesToSubsequentCalls,test_concurrentLevelChanges_completeSafely]
public func setLogLevel(_ level: LogLevel) {
    logLevelLock.lock()
    configuredLogLevel = level
    logLevelLock.unlock()
}

/// Reads the configured threshold while holding the level lock.
private func currentLogLevel() -> LogLevel {
    logLevelLock.lock()
    let level = configuredLogLevel
    logLevelLock.unlock()
    return level
}

/// The level and optional interval-throttling key forwarded to LoggerProtocol.
/// TEST:LogTests[test_logTypeDescriptions_includeAllLevelsAndKeys]
public enum LogType: CustomStringConvertible {
    /// A verbose message with an optional throttling key.
    case verbose(String?)
    /// A debug message with an optional throttling key.
    case debug(String?)
    /// An informational message with an optional throttling key.
    case info(String?)
    /// A warning message with an optional throttling key.
    case warn(String?)
    /// An error message with an optional throttling key.
    case error(String?)

    /// Returns the stable label and associated key used by the recorder.
    /// TEST:LogTests[test_logTypeDescriptions_includeAllLevelsAndKeys]
    public var description: String {
        switch self {
        case .verbose(let string):
            "[#VERBOSE#]\(string, default: "")"
        case .debug(let string):
            "[#DEBUG#]\(string, default: "")"
        case .info(let string):
            "[#INFO#]\(string, default: "")"
        case .warn(let string):
            "[#WARN#]\(string, default: "")"
        case .error(let string):
            "[#ERROR#]\(string, default: "")"
        }
    }
}

/// Converts a public level and key into the associated LogType payload.
/// - Parameters:
///   - level: The severity level selected by the caller.
///   - key: The optional interval-throttling key.
/// - Returns: The associated LogType value for the selected level.
private func makeLogType(for level: LogLevel, key: String?) -> LogType {
    switch level {
    case .verbose:
        .verbose(key)
    case .debug:
        .debug(key)
    case .info:
        .info(key)
    case .warn:
        .warn(key)
    case .error:
        .error(key)
    }
}

/// Logs a message when its level meets the configured process-wide threshold.
/// - Parameters:
///   - message: A deferred message expression evaluated after level filtering; the logger decides when to evaluate it.
///   - level: The severity level of the message.
///   - key: An optional key used for interval throttling.
///   - minIntervalBetweenSameKey: The minimum interval between messages with the same key.
///   - file: The source file that emitted the log.
///   - line: The source line that emitted the log.
///   - function: The source function that emitted the log.
/// Interval throttling is level-specific because the recorder key includes the formatted `LogType`; identical keys at different levels use separate buckets.
/// TEST:LogTests[test_filteredLog_doesNotEvaluateMessage,test_concurrentLevelChanges_completeSafely]
public func log(
    _ message: @escaping @autoclosure () -> CustomStringConvertible,
    level: LogLevel,
    key: String? = nil,
    minIntervalBetweenSameKey: TimeInterval? = nil,
    file: StaticString = #fileID,
    line: Int = #line,
    function: StaticString = #function
) {
    guard level >= currentLogLevel() else {
        return
    }

    let logger = currentLogger()
    logger.log_plain(
        message().description,
        type: makeLogType(for: level, key: key),
        minIntervalBetweenSameKey: minIntervalBetweenSameKey,
        file: file,
        line: line,
        function: function
    )
}

/// Logs an informational message through the common level filter.
/// - Parameters:
///   - message: A deferred informational message.
///   - infoKey: An optional interval-throttling key.
///   - minIntervalBetweenSameKey: The minimum interval between messages with the same key.
///   - file: The source file that emitted the log.
///   - line: The source line that emitted the log.
///   - function: The source function that emitted the log.
/// TEST:LogTests[test_compatibilityWrappers_forwardKeyAndMetadata,test_filteredCompatibilityWrappers_doNotEvaluateMessage]
public func log_info(
    _ message: @escaping @autoclosure () -> CustomStringConvertible,
    infoKey: String? = nil,
    minIntervalBetweenSameKey: TimeInterval? = nil,
    file: StaticString = #fileID,
    line: Int = #line,
    function: StaticString = #function
) {
    log(
        message(),
        level: .info,
        key: infoKey,
        minIntervalBetweenSameKey: minIntervalBetweenSameKey,
        file: file,
        line: line,
        function: function
    )
}

/// Logs a warning message through the common level filter.
/// - Parameters:
///   - message: A deferred warning message.
///   - warnKey: An optional interval-throttling key.
///   - minIntervalBetweenSameKey: The minimum interval between messages with the same key.
///   - file: The source file that emitted the log.
///   - line: The source line that emitted the log.
///   - function: The source function that emitted the log.
/// TEST:LogTests[test_compatibilityWrappers_forwardKeyAndMetadata,test_filteredCompatibilityWrappers_doNotEvaluateMessage]
public func log_warn(
    _ message: @escaping @autoclosure () -> CustomStringConvertible,
    warnKey: String? = nil,
    minIntervalBetweenSameKey: TimeInterval? = nil,
    file: StaticString = #fileID,
    line: Int = #line,
    function: StaticString = #function
) {
    log(
        message(),
        level: .warn,
        key: warnKey,
        minIntervalBetweenSameKey: minIntervalBetweenSameKey,
        file: file,
        line: line,
        function: function
    )
}

/// Logs an error message through the common level filter.
/// - Parameters:
///   - message: A deferred error message.
///   - errKey: An optional interval-throttling key.
///   - minIntervalBetweenSameKey: The minimum interval between messages with the same key.
///   - file: The source file that emitted the log.
///   - line: The source line that emitted the log.
///   - function: The source function that emitted the log.
/// TEST:LogTests[test_compatibilityWrappers_forwardKeyAndMetadata,test_filteredCompatibilityWrappers_doNotEvaluateMessage]
public func log_err(
    _ message: @escaping @autoclosure () -> CustomStringConvertible,
    errKey: String? = nil,
    minIntervalBetweenSameKey: TimeInterval? = nil,
    file: StaticString = #fileID,
    line: Int = #line,
    function: StaticString = #function
) {
    log(
        message(),
        level: .error,
        key: errKey,
        minIntervalBetweenSameKey: minIntervalBetweenSameKey,
        file: file,
        line: line,
        function: function
    )
}
