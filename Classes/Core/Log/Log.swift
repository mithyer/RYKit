//
//  Log.swift
//  RYKit
//
//  Created by ray on 2025/12/9.
//

import Foundation

let default_logger = LogRecorder(logNamePrefix: "default")

fileprivate enum LogType: CustomStringConvertible {
    case info(String?), warn(String?), error(String?)
    
    var description: String {
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

fileprivate func log_plain(_ str: CustomStringConvertible, type: LogType, minIntervalBetweenSameKey: TimeInterval? = nil, file: String = #fileID, line: Int = #line, function: String = #function) {
    default_logger.printAndSaveLog(content: "\(str)", style: .plainText, key: "\(type)", minIntervalBetweenSameKey: minIntervalBetweenSameKey, file: file, line: line, function: function)
}

public func log_info(_ message: CustomStringConvertible, infoKey: String? = nil, minIntervalBetweenSameKey: TimeInterval? = nil, file: String = #fileID, line: Int = #line, function: String = #function) {
    log_plain(message, type: .info(infoKey), minIntervalBetweenSameKey: minIntervalBetweenSameKey, file: file, line: line, function: function)
}

public func log_warn(_ message: CustomStringConvertible, warnKey: String? = nil, minIntervalBetweenSameKey: TimeInterval? = nil, file: String = #fileID, line: Int = #line, function: String = #function) {
    log_plain(message, type: .warn(warnKey), minIntervalBetweenSameKey: minIntervalBetweenSameKey, file: file, line: line, function: function)
}

public func log_err(_ message: CustomStringConvertible, errKey: String? = nil, minIntervalBetweenSameKey: TimeInterval? = nil, file: String = #fileID, line: Int = #line, function: String = #function) {
    log_plain(message, type: .error(errKey), minIntervalBetweenSameKey: minIntervalBetweenSameKey, file: file, line: line, function: function)
}
