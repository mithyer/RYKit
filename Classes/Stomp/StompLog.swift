//
//  StompLog.swift
//  ADKit
//
//  Created by ray on 2025/2/21.
//

import Foundation

func stomp_log(_ str: @autoclosure () -> String, _ logCase: StompLog.ProcessedLogCase = .notice) {
#if DEBUG
    StompLog.log(str(), logCase: logCase)
#endif
}

public struct StompLog {
    
    public enum ProcessedLogCase {
        case notice
        case warning
        case message
        case error
    }

    public static var onReceivedRawLog: ((String) -> Void)?
    
    // 原始的SwiftStomp的代码的log
    public static var enableRawLog: Bool = false
    public static var rawLogFilter: ((_ type : StompRawLogType, _ message : String) -> Bool)?

    // 封装后的代码的log
    public static var enableProcessedLog: Bool = false
    public static var processedLogFilter: ((_ case: ProcessedLogCase, _ message: String) -> Bool)?

    static func log(_ str: String, logCase: ProcessedLogCase) {
        if !enableProcessedLog {
            return
        }
        if let processedLogFilter, !processedLogFilter(logCase, str) {
            return
        }
        switch logCase {
        case .notice:
            print("===== STOMP NOTICE =====>")
            print(str)
            print("<===== NOTICE ===== ")
        case .warning:
            print("===== STOMP WARNING =====>")
            print(str)
            print("<===== WARNING ===== ")
        case .message:
            print("===== STOMP MESSAGE =====>")
            print(str)
            print("<===== MESSAGE ===== ")
        case .error:
            print("===== STOMP ERROR =====>")
            print(str)
            print("<===== ERROR ===== ")
        }
    }
}
