//
//  ExistValue.swift
//  Pods
//
//  Created by ray on 2025/3/27.
//

@propertyWrapper
public struct ExistValue<T: Codable>: Codable, CustomStringConvertible {
    
    public var wrappedValue: T
    public var rawValue: Any?
    
    enum CodingKeys: CodingKey {
        case wrappedValue
    }
    
    public var description: String {
        return "\(wrappedValue)"
    }
    
    public init(wrappedValue: T) {
        self.wrappedValue = wrappedValue
    }
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let value: T = try tryMakeWrapperValue(container: container, rawValue: &rawValue) {
            self.wrappedValue = value
        } else {
            throw DecodingError.valueNotFound(Self.self, DecodingError.Context(codingPath: decoder.codingPath, debugDescription: "ExistValue: value not exist"))
        }
    }
    
    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(self.wrappedValue)
    }
}

public extension KeyedEncodingContainer {
    mutating func encode<T>(_ value: ExistValue<T>, forKey key: Key) throws {
        try encode(value.wrappedValue, forKey: key)
    }
}
