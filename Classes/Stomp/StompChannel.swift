//
//  StompChannel.swift
//  TRSTradingClient
//
//  Created by ray on 2025/1/24.
//

import Foundation

public protocol HandshakeDataProtocol: Decodable {
    var code: Int? { get }
    var handshakeId: String? { get }
    var expiresIn: Int? { get }
    var msg: String? { get }
}

// 连接相关的配置数据
public protocol StompChannel {
    associatedtype HandshakeDataType: HandshakeDataProtocol
    var userToken: String { get set }
    var handshakeURL: String { get }
    var handshakeParams: [String: Any] { get }
    func stompURL(from handshakeData: HandshakeDataType) -> String?
    var stompHeaders: [String: String] { get }
    init(userToken: String)
}

