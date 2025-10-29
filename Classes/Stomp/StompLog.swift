//
//  StompLog.swift
//  ADKit
//
//  Created by ray on 2025/2/21.
//

import Foundation

/// STOMP 内部日志函数，仅在 DEBUG 模式下生效
/// - Parameters:
///   - str: 日志内容（使用 @autoclosure 延迟计算）
///   - logCase: 日志类型，默认为 .notice
func stomp_log(_ str: @autoclosure () -> String, _ logCase: StompLog.ProcessedLogCase = .notice) {
#if DEBUG
    StompLog.log(str(), logCase: logCase)
#endif
}

/// STOMP 日志管理器，用于控制日志的输出和过滤
public struct StompLog {
    
    /// 处理后的日志类型
    public enum ProcessedLogCase {
        /// 普通通知
        case notice
        /// 警告信息
        case warning
        /// 消息内容
        case message
        /// 错误信息
        case error
    }

    /// 接收原始日志的回调
    public static var onReceivedRawLog: ((String) -> Void)?
    
    /// 是否启用原始 SwiftStomp 库的日志
    public static var enableRawLog: Bool = false
    
    /// 原始日志过滤器，返回 true 则输出该日志
    public static var rawLogFilter: ((_ type : StompRawLogType, _ message : String) -> Bool)?

    /// 是否启用封装后的代码日志
    public static var enableProcessedLog: Bool = false
    
    /// 处理后的日志过滤器，返回 true 则输出该日志
    public static var processedLogFilter: ((_ case: ProcessedLogCase, _ message: String) -> Bool)?

    /// 输出日志到控制台
    /// - Parameters:
    ///   - str: 日志内容
    ///   - logCase: 日志类型
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
