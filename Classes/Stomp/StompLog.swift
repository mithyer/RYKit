//
//  StompLog.swift
//  ADKit
//
//  Created by ray on 2025/2/21.
//

import Foundation

func stomp_log(_ str: @autoclosure () -> String, _ logCase: StompLog.LogCase = .notice, _ level: StompLog.Level = .basic) {
#if DEBUG
    StompLog.log(str(), level: level, logCase: logCase)
#endif
}

public struct StompLog {
    
    public enum Level: Int {
        case none
        case basic
        case all
    }
    
    enum LogCase {
        case notice
        case warning
        case message
        case error
    }
    
    public static var level: Level = .basic
    
    static func log(_ str: String, level: Level, logCase: LogCase) {
        let limitLevel = self.level
        if level.rawValue > limitLevel.rawValue {
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
