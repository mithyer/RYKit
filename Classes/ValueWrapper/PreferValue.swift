//
//  PreferValue.swift
//  TRSTradingClient
//
//  Created by ray on 2025/2/12.
//

// Decode时将Optional的不同类型尝试转换为已声明类型，若都不能转换则设为nil，避免类型不同时throw error

import Foundation

@propertyWrapper
public struct PreferValue<T: Codable>: Codable, CustomDebugStringConvertible {
    
    public var wrappedValue: T?
    public var rawValue: Any?
    
    enum CodingKeys: CodingKey {
        case wrappedValue
    }
    
    public var debugDescription: String {
        return "\(nil != wrappedValue ? "\(wrappedValue!)" : "null")| \(rawValue ?? "")"
    }
    
    public init() {}
    
    public init(wrappedValue: T?) {
        self.wrappedValue = wrappedValue
    }
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()

        if container.decodeNil() {
            return
        }
        
        self.wrappedValue = tryMakeWrapperValue(container: container, rawValue: &rawValue)
    }
}

public extension KeyedDecodingContainer {
    func decode<T>(_: PreferValue<T>.Type, forKey key: Key) throws -> PreferValue<T> where T: Decodable {
        if let value = try? decodeIfPresent(PreferValue<T>.self, forKey: key) {
            return value
        }
        if let value = try? decodeIfPresent(T.self, forKey: key) {
            return PreferValue(wrappedValue: value)
        }
        return PreferValue()
    }
}

public extension KeyedEncodingContainer {
    mutating func encode<T>(_ value: PreferValue<T>, forKey key: Key) throws {
        try encode(value.wrappedValue, forKey: key)
    }
}
