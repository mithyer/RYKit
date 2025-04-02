//
//  IgnoreValue.swift
//  TRSTradingClient
//
//  Created by ray on 2025/4/1.
//

// Codable的Model中有此声明的变量不参与Codable

import Foundation

@propertyWrapper
public struct IgnoreValue<T>: Codable, CustomDebugStringConvertible, CustomStringConvertible {
    
    public var wrappedValue: T?
    
    enum CodingKeys: CodingKey {}
    
    public var description: String {
        if let wrappedValue {
            return "\(wrappedValue)"
        }
        return "nil"
    }
    
    public var debugDescription: String {
        return "\(T.self): \(nil != wrappedValue ? "\(wrappedValue!) " : "nil") | Any?: nil"
    }
    
    public init() {}
    
    public init(wrappedValue: T?) {
        self.wrappedValue = wrappedValue
    }
    
    public init(from decoder: Decoder) throws {}
    
    public func encode(to encoder: any Encoder) throws {}
}

public extension KeyedDecodingContainer {
    func decode<T>(_: IgnoreValue<T>.Type, forKey key: Key) throws -> IgnoreValue<T> where T: Decodable {
        return IgnoreValue()
    }
}

public extension KeyedEncodingContainer {
    mutating func encode<T>(_ value: IgnoreValue<T>, forKey key: Key) throws {}
}
