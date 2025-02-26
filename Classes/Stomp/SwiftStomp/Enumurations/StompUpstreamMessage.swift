//
//  StompUpstreamMessage.swift
//  Pods
//
//  Created by Ahmad Daneshvar on 5/16/24.
//

import Foundation

enum StompUpstreamMessage {
    case text(message : String, messageId : String, destination : String, headers : [String : String])
    case data(data: Data,  messageId : String, destination : String, headers : [String : String])
    
    var subscriptionID: String? {
        switch self {
        case .text(let message, let messageId, let destination, let headers):
            return headers[StompCommonHeader.subscription.rawValue]
        case .data(let data, let messageId, let destination, let headers):
            return headers[StompCommonHeader.subscription.rawValue]
        }
    }
}
