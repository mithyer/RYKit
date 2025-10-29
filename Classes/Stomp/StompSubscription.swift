//
//  StompSubscription.swift
//  TRSTradingClient
//
//  Created by ray on 2025/1/25.
//

import Foundation

/// STOMP 订阅信息类，用于描述一个订阅的详细信息
/// 相同的 destination 和 identifier 被认为是同一个订阅
public class StompSubInfo: CustomDebugStringConvertible {
    
    /// 订阅的目标地址（STOMP destination）
    public let destination: String
    
    /// 订阅时使用的额外请求头
    public let headers: [String: String]?
    
    /// 订阅的唯一标识符，用于区分同一 destination 的不同订阅回调
    public let identifier: String
    
    /// 初始化订阅信息
    /// - Parameters:
    ///   - identifier: 订阅标识符
    ///   - destination: 目标地址
    ///   - headers: 可选的请求头
    public init(identifier: String, destination: String, headers: [String : String]?) {
        self.destination = destination
        self.headers = headers
        self.identifier = identifier
    }
    
    /// 生成唯一的 STOMP ID，用于内部标识订阅
    /// - Parameter token: 用户令牌
    /// - Returns: 包含用户、目标地址和请求头的唯一标识符
    func stompID(token: String) -> String {
        "user: \(token), destination: \(destination)\(nil == headers ? "" : ", subHeaders: \(headers!.sortedURLParams)")"
    }
    
    /// 调试描述信息
    public var debugDescription: String {
        "\(destination) | identifier: \(identifier) | subHeaders:\(headers ?? [:])) "
    }
}
