//
//  PreferValue.swift
//  TRSTradingClient
//
//  Created by ray on 2025/2/12.
//

// Decode时将Optional的不同类型尝试转换为已声明类型，若都不能转换则设为nil，避免类型不同时throw error

import Foundation

@propertyWrapper
public struct PreferValue<T: Codable>: Codable, CustomDebugStringConvertible, CustomStringConvertible {
    
    public var wrappedValue: T?
    public var rawValue: Any?
    
    enum CodingKeys: CodingKey {
        case wrappedValue
    }
    
    public var description: String {
        if let wrappedValue {
            return "\(wrappedValue)"
        }
        return "nil"
    }
    
    public var debugDescription: String {
        if let rawValue = rawValue {
            return "\(T.self): \(nil != wrappedValue ? "\(wrappedValue!) " : "nil") | \(type(of: rawValue)): \(rawValue)"
        }
        return "\(T.self): \(nil != wrappedValue ? "\(wrappedValue!) " : "nil") | Any?: nil"
    }
    
    public init() {}
    
    public init(wrappedValue: T?) {
        self.wrappedValue = wrappedValue
    }
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        self.wrappedValue = try? tryMakeWrapperValue(container: container, rawValue: &rawValue)
    }
    
    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(self.wrappedValue)
    }
}

public extension KeyedDecodingContainer {
    func decode<T>(_: PreferValue<T>.Type, forKey key: Key) throws -> PreferValue<T> where T: Decodable {
        if let value = try? decodeIfPresent(PreferValue<T>.self, forKey: key) {
            return value
        }
        return PreferValue()
    }
}

public extension KeyedEncodingContainer {
    mutating func encode<T>(_ value: PreferValue<T>, forKey key: Key) throws {
        try encode(value.wrappedValue, forKey: key)
    }
}
