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
    
    func stompID(token: String) -> String {
        "user: \(token), destination: \(destination)\(nil == headers ? "" : ", headers: \(headers!.sortedURLParams)")"
    }
    
    public var debugDescription: String {
        "\(destination) | identifier: \(identifier) | headers:\(headers ?? [:])) "
    }
}
