//
//  Log.swift
//  RYKit
//
//  Created by ray on 2025/12/9.
//

import Foundation

public protocol LoggerProtocol {
    
    static func log_plain(_ str: @escaping @autoclosure () -> String, type: LogType, minIntervalBetweenSameKey: TimeInterval?, file: StaticString, line: Int, function: StaticString)
}

struct DefaultLogger: LoggerProtocol {
    
    static let recorder = LogRecorder(logNamePrefix: "default")
    
    static func log_plain(_ str: @escaping @autoclosure () -> String, type: LogType, minIntervalBetweenSameKey: TimeInterval?, file: StaticString, line: Int, function: StaticString) {
        #if DEBUG
        recorder.printAndSaveLog(content: str(), style: .plainText, key: "\(type)", minIntervalBetweenSameKey: minIntervalBetweenSameKey, file: file, line: line, function: function)
        #endif
    }
}

private var activeLogger: LoggerProtocol.Type = DefaultLogger.self
public func setActiveLogger(_ logger: LoggerProtocol.Type) {
    activeLogger =  logger
}

public enum LogType: CustomStringConvertible {
    case info(String?), warn(String?), error(String?)
    
    public var description: String {
        switch self {
        case .info(let string):
            "[#INFO#]\(string, default: "")"
        case .warn(let string):
            "[#WARN#]\(string, default: "")"
        case .error(let string):
            "[#ERROR#]\(string, default: "")"
        }
    }
}

public func log_info(_ message: CustomStringConvertible, infoKey: String? = nil, minIntervalBetweenSameKey: TimeInterval? = nil, file: StaticString = #fileID, line: Int = #line, function: StaticString = #function) {
    activeLogger.log_plain(message.description, type: .info(infoKey), minIntervalBetweenSameKey: minIntervalBetweenSameKey, file: file, line: line, function: function)
}

public func log_warn(_ message: CustomStringConvertible, warnKey: String? = nil, minIntervalBetweenSameKey: TimeInterval? = nil, file: StaticString = #fileID, line: Int = #line, function: StaticString = #function) {
    activeLogger.log_plain(message.description, type: .warn(warnKey), minIntervalBetweenSameKey: minIntervalBetweenSameKey, file: file, line: line, function: function)
}

public func log_err(_ message: CustomStringConvertible, errKey: String? = nil, minIntervalBetweenSameKey: TimeInterval? = nil, file: StaticString = #fileID, line: Int = #line, function: StaticString = #function) {
    activeLogger.log_plain(message.description, type: .error(errKey), minIntervalBetweenSameKey: minIntervalBetweenSameKey, file: file, line: line, function: function)
}
