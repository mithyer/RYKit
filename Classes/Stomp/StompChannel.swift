//
//  StompChannel.swift
//  TRSTradingClient
//
//  Created by ray on 2025/1/24.
//

import Foundation

/// 握手数据协议，定义握手请求返回的数据结构
public protocol HandshakeDataProtocol: Decodable {
    /// 响应状态码，通常 200 表示成功
    var code: Int? { get }
    /// 握手 ID，用于后续的 WebSocket 连接
    var handshakeId: String? { get }
    /// 握手 ID 的有效期（秒）
    var expiresIn: Int? { get }
    /// 响应消息
    var msg: String? { get }
}

/// STOMP 连接通道协议，定义连接相关的配置数据
/// 使用者需要实现此协议来提供连接所需的各种参数
public protocol StompChannel {
    /// 握手数据类型，必须遵循 HandshakeDataProtocol
    associatedtype HandshakeDataType: HandshakeDataProtocol
    
    /// 用户令牌，用于身份验证
    var userToken: String { get set }
    
    /// 握手请求的 URL
    var handshakeURL: String { get }
    
    /// 握手请求的参数
    var handshakeParams: [String: Any] { get }
    
    /// 根据握手数据生成 STOMP WebSocket URL
    /// - Parameter handshakeData: 握手响应数据
    /// - Returns: WebSocket 连接 URL
    func stompURL(from handshakeData: HandshakeDataType) -> String?
    
    /// STOMP 连接时使用的请求头
    var stompHeaders: [String: String] { get }
    
    /// 初始化方法
    /// - Parameter userToken: 用户令牌
    init(userToken: String)
}

