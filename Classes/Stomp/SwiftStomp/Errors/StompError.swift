//
//  StompError.swift
//  Pods
//
//  Created by Ahmad Daneshvar on 5/16/24.
//

public enum StompError: Error {
    case fromStomp(description: String, receiptId: String)
    case fromSocket(error: Error)
    
    public var description: String {
        switch self {
        case .fromStomp(let desp, let receiptId):
            return "FromStompError: receiptId: \(String(describing: receiptId)), \(desp)"
        case .fromSocket(let error):
            return "FromSocketError: \(error)"
        }
    }
}

//public struct StompError: Error {
//    public let localizedDescription: String
//    public let receiptId: String?
//    public let type: StompErrorType
//    
//    
//    init(type: StompErrorType, receiptId: String?, localizedDescription: String) {
//        self.localizedDescription = localizedDescription
//        self.receiptId = receiptId
//        self.type = type
//    }
//    
//    init(error: Error, type: StompErrorType) {
//        self.localizedDescription = error.localizedDescription
//        self.receiptId = nil
//        self.type = type
//    }
//}
//
//extension StompError: CustomStringConvertible {
//    public var description: String {
//        "StompError(\(type)) [receiptId: \(String(describing: receiptId))]: \(localizedDescription)"
//    }
//}
