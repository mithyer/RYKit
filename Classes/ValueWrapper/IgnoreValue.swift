//
//  IgnoreValue.swift
//  Pods
//
//  Created by ray on 2025/9/1.
//

// 被标记的值不会参与Codable
@propertyWrapper
public struct IgnoreValue<T>: Codable, CustomStringConvertible {
    
    public var wrappedValue: T?
    
    public var description: String {
        return "\(String(describing: wrappedValue))"
    }
    
    public init(wrappedValue: T?) {
        self.wrappedValue = wrappedValue
    }
    
    public init(from decoder: Decoder) throws {}
    
    public func encode(to encoder: any Encoder) throws {}
}

public extension KeyedEncodingContainer {
    mutating func encode<T>(_ value: IgnoreValue<T>, forKey key: Key) throws {}
}

public extension KeyedDecodingContainer {
    
    func decode<T>(_: IgnoreValue<T>.Type, forKey key: Key) throws -> IgnoreValue<T> where T: Decodable {
        return IgnoreValue(wrappedValue: nil)
    }
    
    func decodeIfPresent<T>(_: IgnoreValue<T>.Type, forKey key: Key) throws -> IgnoreValue<T>? {
         return IgnoreValue(wrappedValue: nil)
    }
}
