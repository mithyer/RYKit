//
//  StompSubscription.swift
//  TRSTradingClient
//
//  Created by ray on 2025/1/25.
//

import Foundation

// 订阅协议
public protocol StompSubscription: CustomDebugStringConvertible {
    
    var destination: String { get }
    var identifier: String { get }
    var subscribeHeaders: [String: String]? { get }
    var unsubscribeHeaders: [String: String]? { get }
    var callbackKey: String { get }
}

public extension StompSubscription {
    
    var callbackKey: String { identifier }
    var subscribeHeaders: [String: String]? {
        [StompCommonHeader.id.rawValue: identifier]
    }
    var unsubscribeHeaders: [String: String]? {
        [StompCommonHeader.id.rawValue: identifier]
    }
    var debugDescription: String {
        "\(destination) | \(identifier) | subscribeHeaders:\(subscribeHeaders ?? [:]) | unsubscribeHeaders:\(unsubscribeHeaders ?? [:]))"
    }
}
