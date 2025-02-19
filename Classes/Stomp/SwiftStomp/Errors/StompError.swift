//
//  StompError.swift
//  Pods
//
//  Created by Ahmad Daneshvar on 5/16/24.
//

enum StompError: Error {
    case fromStomp(description: String, receiptId: String)
    case fromSocket(error: Error)
    
    var description: String {
        switch self {
        case .fromStomp(let desp, let receiptId):
            return "FromStompError: receiptId: \(String(describing: receiptId)), \(desp)"
        case .fromSocket(let error):
            return "FromSocketError: \(error)"
        }
    }
}

//struct StompError: Error {
//    let localizedDescription: String
//    let receiptId: String?
//    let type: StompErrorType
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
//    var description: String {
//        "StompError(\(type)) [receiptId: \(String(describing: receiptId))]: \(localizedDescription)"
//    }
//}
