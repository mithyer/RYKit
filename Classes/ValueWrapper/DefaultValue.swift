//
//  DefaultValue.swift
//  TRSTradingClient
//
//  Created by ray on 2025/2/9.
//

// Decode时将非Optional的值设置默认值，并且会尝试将其他类型值转换为已声明类型，避免不存在该键值时throw error

import Foundation

@propertyWrapper
public struct DefaultValue<Provider: DefaultValueProvider>: Codable, CustomDebugStringConvertible {
    
    public var wrappedValue: Provider.Value
    private var useDefaultValue = true
    private var decodedRawValueDescription: String?

    public var debugDescription: String {
        return "\(useDefaultValue ? "default": "parsed"): \(wrappedValue) | \(decodedRawValueDescription ?? "")"
    }
    
    public init() {
        wrappedValue = Provider.default
    }

    public init(wrappedValue: Provider.Value) {
        self.wrappedValue = wrappedValue
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()

        if container.decodeNil() {
            wrappedValue = Provider.default
        } else {
            let value: Provider.Value? = tryMakeWrapperValue(container: container, decodedRawValueDescription: &decodedRawValueDescription)
            if let value = value {
                wrappedValue = value
                useDefaultValue = false
            } else {
                wrappedValue = Provider.default
            }
        }
    }
}

func tryMakeWrapperValue<T: Decodable>(container: any SingleValueDecodingContainer, decodedRawValueDescription: inout String?) -> T? {
    var value = try? container.decode(T.self)
    if nil != value {
        return value
    }
    if T.self == Int.self {
        if let string = try? container.decode(String.self) {
            value = Int(string) as? T
            decodedRawValueDescription = "string: \(string)"
        } else if let double = try? container.decode(Double.self) {
            value = Int(double) as? T
            decodedRawValueDescription = "double: \(double)"
        }
    } else if T.self == Double.self {
        if let string = try? container.decode(String.self) {
            value = Double(string) as? T
            decodedRawValueDescription = "string: \(string)"
        }
    } else if T.self == String.self {
        if let int = try? container.decode(Int.self) {
            value = "\(int)" as? T
            decodedRawValueDescription = "int: \(int)"
        } else if let double = try? container.decode(Double.self) {
            value = "\(double)" as? T
            decodedRawValueDescription = "double: \(double)"
        }
    } else if T.self == Bool.self {
        if let string = try? container.decode(String.self) {
            value = ["true", "y", "t", "yes", "1"].contains { string.caseInsensitiveCompare($0) == .orderedSame } as? T
            decodedRawValueDescription = "string: \(string)"
        } else if let int = try? container.decode(Int.self) {
            if int == 1 {
                value = true as? T
                decodedRawValueDescription = "int: \(int)"
            } else if int == 0 {
                value = false as? T
                decodedRawValueDescription = "int: \(int)"
            }
        }
    } else {
        if let string = try? container.decode(String.self) {
            decodedRawValueDescription = string
            if let data = string.data(using: .utf8) {
                value = try? JSONDecoder().decode(T.self, from: data)
            }
        }
    }
    return value
}

extension DefaultValue: Equatable where Provider.Value: Equatable {}
extension DefaultValue: Hashable where Provider.Value: Hashable {}

public extension KeyedDecodingContainer {
    func decode<P>(_: DefaultValue<P>.Type, forKey key: Key) throws -> DefaultValue<P> {
        if let value = try decodeIfPresent(DefaultValue<P>.self, forKey: key) {
            return value
        } else {
            return DefaultValue()
        }
    }
}

public extension KeyedEncodingContainer {
    mutating func encode<P>(_ value: DefaultValue<P>, forKey key: Key) throws {
        try encode(value.wrappedValue, forKey: key)
    }
}

// DefaultValueProvider

public protocol DefaultValueProvider {
    associatedtype Value: Codable

    static var `default`: Value { get }
}

public protocol Initilizable {
    
    init()
}

extension NSObject: Initilizable {}
extension String: Initilizable {}
extension Int: Initilizable {}
extension Double: Initilizable {}
extension Bool: Initilizable {}
extension Dictionary: Initilizable {}
extension Array: Initilizable {}
extension Set: Initilizable {}

public struct Provider {
    
    public enum BoolFalse: DefaultValueProvider {
        public static let `default` = false
    }

    public enum BoolTrue: DefaultValueProvider {
        public static let `default` = true
    }
    
    public enum IntZero: DefaultValueProvider {
        public static let `default` = 0
    }

    public enum DoubleZero: DefaultValueProvider {
        public static let `default`: Double = 0
    }
    
    public enum StringEmpty: DefaultValueProvider {
        public static let `default` = ""
    }
    
    public enum DecimalZero: DefaultValueProvider {
        public static let `default` = Decimal(exactly: 0)
    }
    
    public enum ArrayEmpty<A>: DefaultValueProvider where A: Codable & RangeReplaceableCollection {
        public static var `default`: A { A() }
    }
    
    public enum DicEmpty<K, V>: DefaultValueProvider where K: Hashable & Codable, V: Codable {
        public static var `default`: [K: V] { Dictionary() }
    }
    
    public enum CaseFirst<A>: DefaultValueProvider where A: Codable & CaseIterable {
        public static var `default`: A { A.allCases.first! }
    }
    
    public enum Init<A>: DefaultValueProvider where A: Initilizable & Codable {
        public static var `default`: A  { A() }
    }
}

public struct Default {
    
    public typealias BoolFalse = DefaultValue<Provider.BoolFalse>
    public typealias BoolTrue = DefaultValue<Provider.BoolTrue>
    public typealias IntZero = DefaultValue<Provider.IntZero>
    public typealias DoubleZero = DefaultValue<Provider.DoubleZero>
    public typealias StringEmpty = DefaultValue<Provider.StringEmpty>
    public typealias ArrayEmpty<A: Codable & RangeReplaceableCollection> = DefaultValue<Provider.ArrayEmpty<A>>
    public typealias DicEmpty<K: Hashable & Codable, V: Codable> = DefaultValue<Provider.DicEmpty<K, V>>
    public typealias CaseFirst<A: Codable & CaseIterable> = DefaultValue<Provider.CaseFirst<A>>
}

