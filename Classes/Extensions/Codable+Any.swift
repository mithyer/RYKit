//
//  Codable+Any.swift
//  Pods
//
//  Created by ray on 2025/3/26.
//

// Make [String: Any], [Any] Codable !!
// inspired by https://gist.github.com/loudmouth/332e8d89d8de2c1eaf81875cfcd22e24

import Foundation


public struct JSONCodingKeys: CodingKey {
    public var stringValue: String
    public var intValue: Int?
    
    public init(stringValue: String) {
        self.stringValue = stringValue
    }
    
    public init?(intValue: Int) {
        self.init(stringValue: "\(intValue)")
        self.intValue = intValue
    }
}

public extension KeyedDecodingContainer {
    
    func decode(_ type: [String: Any].Type, forKey key: K) throws -> [String: Any] {
        let container = try self.nestedContainer(keyedBy: JSONCodingKeys.self, forKey: key)
        return try container.decode(type)
    }
    
    func decodeIfPresent(_ type: [String: Any].Type, forKey key: K) throws -> [String: Any]? {
        guard contains(key) else {
            return nil
        }
        if try decodeNil(forKey: key) {
            return nil
        }
        return try decode(type, forKey: key)
    }
    
    func decode(_ type: [Any].Type, forKey key: K) throws -> [Any] {
        var container = try self.nestedUnkeyedContainer(forKey: key)
        return try container.decode(type)
    }
    
    func decode(_ type: [[String: Any]].Type, forKey key: K) throws -> [[String: Any]] {
        var container = try self.nestedUnkeyedContainer(forKey: key)
        return try container.decode(type)
    }
    
    func decodeIfPresent(_ type: [Any].Type, forKey key: K) throws -> [Any]? {
        guard contains(key) else {
            return nil
        }
        if try decodeNil(forKey: key) {
            return nil
        }
        return try decode(type, forKey: key)
    }
    
    func decode(_ type: [String: Any].Type) throws -> [String: Any] {
        var dictionary = [String: Any]()
        
        for key in allKeys {
            if let boolValue = try? decode(Bool.self, forKey: key) {
                dictionary[key.stringValue] = boolValue
            } else if let intValue = try? decode(Int.self, forKey: key) {
                dictionary[key.stringValue] = intValue
            } else if let decimalValue = try? decode(Decimal.self, forKey: key) {
                dictionary[key.stringValue] = decimalValue
            } else if let stringValue = try? decode(String.self, forKey: key) {
                dictionary[key.stringValue] = stringValue
            } else if let nestedDictionary = try? decode(Dictionary<String, Any>.self, forKey: key) {
                dictionary[key.stringValue] = nestedDictionary
            } else if let nestedArray = try? decode(Array<Any>.self, forKey: key) {
                dictionary[key.stringValue] = nestedArray
            } else if let value = try? decodeNil(forKey: key), value {
                //saving NSNull values in a dictionary will produce unexpected results for users, just skip
            }
        }
        return dictionary
    }
    
    func decodeIfPresent<T: Decodable>(forKey key: K, defaultValue: T) -> T {
        do {
            //below will throw
            return try self.decodeIfPresent(T.self, forKey: key) ?? defaultValue
        } catch {
            return defaultValue
        }
    }
    
}

public extension UnkeyedDecodingContainer {
    
    mutating func decode(_ type: [[String: Any]].Type) throws -> [[String: Any]] {
        var array: [[String: Any]] = []
        while isAtEnd == false {
            if let nestedDictionary = try? decode(Dictionary<String, Any>.self) {
                array.append(nestedDictionary)
            }
        }
        return array
    }
    
    mutating func decode(_ type: [Any].Type) throws -> [Any] {
        var array: [Any] = []
        while isAtEnd == false {
            if let value = try? decode(Bool.self) {
                array.append(value)
            } else if let value = try? decode(Int.self) {
                array.append(value)
            } else if let value = try? decode(Decimal.self) {
                array.append(value)
            } else if let value = try? decode(String.self) {
                array.append(value)
            } else if let nestedDictionary = try? decode(Dictionary<String, Any>.self) {
                array.append(nestedDictionary)
            } else if let nestedArray = try? decodeNestedArray(Array<Any>.self) {
                array.append(nestedArray)
            } else if let value = try? decodeNil(), value {
                array.append(NSNull()) //unavoidable, but should be fine. We return [Any]. An overload to return homegenous array would be nice.
            } else {
                //if the right type is not found, it will get stuck in an infinite loop, throw, we can't handle it
                throw EncodingError.invalidValue("<UNKNOWN TYPE>", EncodingError.Context(codingPath: codingPath, debugDescription: "<UNKNOWN TYPE>"))
            }
        }
        
        return array
    }
    
    mutating func decodeNestedArray(_ type: [Any].Type) throws -> [Any] {
        // throws: `CocoaError.coderTypeMismatch` if the encountered stored value is not an unkeyed container.
        var nestedContainer = try self.nestedUnkeyedContainer()
        return try nestedContainer.decode(Array<Any>.self)
    }
    
    mutating func decode(_ type: [String: Any].Type) throws -> [String: Any] {
        // throws: `CocoaError.coderTypeMismatch` if the encountered stored value is not a keyed container.
        let nestedContainer = try self.nestedContainer(keyedBy: JSONCodingKeys.self)
        return try nestedContainer.decode(type)
    }
}

public extension KeyedEncodingContainerProtocol where Key == JSONCodingKeys {
    
    mutating func encode(_ value: [String: Any]) throws {

        for (key, value) in value {
            let key = JSONCodingKeys(stringValue: key)
            switch value {
            case let value as Bool:
                try encode(value, forKey: key)
            case let value as any Numeric:
                if value is any BinaryInteger, let int = Int("\(value)") {
                    try encode(int, forKey: key)
                } else if value is Decimal {
                    try encode(value as! Decimal, forKey: key)
                } else if value is any FloatingPoint, let double = Double("\(value)") {
                    try encode(double, forKey: key)
                } else {
                    throw EncodingError.invalidValue(value, EncodingError.Context(codingPath: codingPath + [key], debugDescription: "Invalid JSON Number"))
                }
            case let value as NSNumber:
                if value is NSDecimalNumber {
                    try encode(value.decimalValue, forKey: key)
                } else if value == kCFBooleanTrue || value == kCFBooleanFalse {
                    try encode(value.boolValue, forKey: key)
                } else if value.decimalValue == Decimal(value.intValue) {
                    try encode(value.intValue, forKey: key)
                } else {
                    try encode(value.doubleValue, forKey: key)
                }
            case let value as String:
                try encode(value, forKey: key)
            case let value as [String: Any]:
                try encode(value, forKey: key)
            case let value as [Any]:
                try encode(value, forKey: key)
            case is NSNull:
                try encodeNil(forKey: key)
            case Optional<Any>.none:
                try encodeNil(forKey: key)
            default:
                throw EncodingError.invalidValue(value, EncodingError.Context(codingPath: codingPath + [key], debugDescription: "Invalid JSON value"))
            }
        }
    }
}

public extension KeyedEncodingContainerProtocol {
    mutating func encode(_ value: [String: Any]?, forKey key: Key) throws {
        guard let value = value else { return }
        
        var container = nestedContainer(keyedBy: JSONCodingKeys.self, forKey: key)
        try container.encode(value)
    }
    
    mutating func encode(_ value: [Any]?, forKey key: Key) throws {
        guard let value = value else { return }
        
        var container = nestedUnkeyedContainer(forKey: key)
        try container.encode(value)
    }
}

public extension UnkeyedEncodingContainer {
    
    mutating func encode(_ value: [Any]) throws {
        for (index, value) in value.enumerated() {
            switch value {
            case let value as Bool:
                try encode(value)
            case let value as any Numeric:
                if value is any BinaryInteger, let int = Int("\(value)") {
                    try encode(int)
                } else if value is Decimal {
                    try encode(value as! Decimal)
                } else if value is any FloatingPoint, let double = Double("\(value)") {
                    try encode(double)
                } else {
                    let keys = JSONCodingKeys(intValue: index).map({ [ $0 ] }) ?? []
                    throw EncodingError.invalidValue(value, EncodingError.Context(codingPath: codingPath + keys, debugDescription: "Invalid JSON Number"))
                }
            case let value as NSNumber:
                if value is NSDecimalNumber {
                    try encode(value.decimalValue)
                } else if value == kCFBooleanTrue || value == kCFBooleanFalse {
                    try encode(value.boolValue)
                } else if value.decimalValue == Decimal(value.intValue) {
                    try encode(value.intValue)
                } else {
                    try encode(value.doubleValue)
                }
            case let value as String:
                try encode(value)
            case let value as [String: Any]:
                try encode(value)
            case let value as [Any]:
                try encodeNestedArray(value)
            case is NSNull:
                try encodeNil()
            case Optional<Any>.none:
                try encodeNil()
            default:
                let keys = JSONCodingKeys(intValue: index).map({ [ $0 ] }) ?? []
                throw EncodingError.invalidValue(value, EncodingError.Context(codingPath: codingPath + keys, debugDescription: "Invalid JSON value"))
            }
        }
    }
    
    mutating func encode(_ value: [String: Any]) throws {
        var container = nestedContainer(keyedBy: JSONCodingKeys.self)
        try container.encode(value)
    }
    
    mutating func encodeNestedArray(_ value: [Any]) throws {
        var container = nestedUnkeyedContainer()
        try container.encode(value)
    }
}

public struct CodableDictionary: Codable {
    public private(set) var dictionary: [String: Any]
    
    public init(_ dictionary: [String: Any]) {
        self.dictionary = dictionary
    }
    
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: JSONCodingKeys.self)
        dictionary = try container.decode([String: Any].self)
    }
    
    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: JSONCodingKeys.self)
        try container.encode(dictionary)
    }
    
    public subscript(_ key: String) -> Any? {
        let keyPaths = key.split(separator: ".")
        var next: Any? = dictionary
        for key in keyPaths {
            if let dic = next as? [String: Any] {
                next = dic[String(key)]
            } else if let arr = next as? [Any],
                      let index = Int(String(key)), index >= 0, index < arr.count {
                next = arr[index]
            } else {
                return nil
            }
        }
        return next
    }
}

public struct CodableArray: Codable {
    public private(set) var array: [Any]
    
    public init(_ array: [Any]) {
        self.array = array
    }
    
    public init(from decoder: any Decoder) throws {
        var container = try decoder.unkeyedContainer()
        array = try container.decode([Any].self)
    }
    
    public func encode(to encoder: any Encoder) throws {
        var container = encoder.unkeyedContainer()
        try container.encode(array)
    }
    
    public subscript(_ index: Int) -> Any? {
        guard index >= 0, index < array.count else {
            return nil
        }
        return array[index]
    }
}
