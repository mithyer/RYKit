//
//  StompSubscription.swift
//  TRSTradingClient
//
//  Created by ray on 2025/1/25.
//

import Foundation


public class StompSubInfo: CustomDebugStringConvertible {
    
    public let destination: String
    public let headers: [String: String]?
    public let identifier: String
    
    public init(identifier: String, destination: String, headers: [String : String]?) {
        self.destination = destination
        self.headers = headers
        self.identifier = identifier
    }
    
    private var stompIDDic = [String: String]()
    public func stompID(token: String) -> String {
        var stompID = stompIDDic[token]
        if nil == stompID {
            stompID = "user: \(token), destination: \(destination)\(nil == headers ? "" : ", headers: \(headers!.sortedURLParams)")"
            stompIDDic[token] = stompID
        }
        return stompID!
    }
    
    public var debugDescription: String {
        "\(destination) | identifier: \(identifier) | headers:\(headers ?? [:])) "
    }
}
