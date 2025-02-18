//
//  DecodeFromStringValue.swift
//  TRSTradingClient
//
//  Created by ray on 2025/2/18.
//

// Decode将string的值直接转换为model

import Foundation

@propertyWrapper
struct DecodeFromStringValue<T: Decodable>: Decodable, CustomDebugStringConvertible {
    
    private(set) var wrappedValue: T?
    private(set) var rawString: String?
    
    var debugDescription: String {
        return "raw: \(rawString ?? "")"
    }
    
    init(wrappedValue: T? = nil) {
        self.wrappedValue = wrappedValue
    }
    
    init(from decoder: Decoder) throws {
    
        let container = try? decoder.singleValueContainer()
        let stringValue = try? container?.decode(String.self)
        
        guard let stringValue = stringValue else {
            self.wrappedValue = nil
            return
        }
        
        rawString = stringValue
        if let data = stringValue.data(using: .utf8) {
            self.wrappedValue = try? JSONDecoder().decode(T.self, from: data)
        } else {
            self.wrappedValue = nil
        }
    }
}
