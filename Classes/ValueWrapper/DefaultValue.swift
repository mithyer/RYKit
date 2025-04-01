//
//  DefaultValue.swift
//  TRSTradingClient
//
//  Created by ray on 2025/2/9.
//

// Decode时将非Optional的值设置默认值，并且会尝试将其他类型值转换为已声明类型，避免不存在该键值时throw error

import Foundation

@propertyWrapper
public struct DefaultValue<Provider: DefaultValueProvider>: Codable, CustomDebugStringConvertible, CustomStringConvertible {
    
    public var wrappedValue: Provider.Value
    private var useDefaultValue = true
    private var rawValue: Any?
    
    enum CodingKeys: CodingKey {
        case wrappedValue
    }
    
    public var debugDescription: String {
        if let rawValue = rawValue {
            return "\(Provider.Value.self): \(wrappedValue) | \(type(of: rawValue)): \(rawValue)"
        }
        return "\(Provider.Value.self): \(wrappedValue) | Any?: nil"
    }

    public var description: String {
        return "\(wrappedValue)"
    }
    
    public init() {
        wrappedValue = Provider.default
    }

    public init(wrappedValue: Provider.Value) {
        self.wrappedValue = wrappedValue
        self.useDefaultValue = false
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let value: Provider.Value? = try? tryMakeWrapperValue(container: container, rawValue: &rawValue)
        if let value {
            wrappedValue = value
            useDefaultValue = false
        } else {
            wrappedValue = Provider.default
        }
    }
    
    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(self.wrappedValue)
    }
}

func tryMakeWrapperValue<T: Decodable>(container: any SingleValueDecodingContainer, rawValue: inout Any?) throws -> T? {
    if container.decodeNil() {
        return nil
    }
    var value = try? container.decode(T.self)
    if nil != value {
        return value
    }
    if T.self == Int.self {
        if let decimal = try? container.decode(Decimal.self) {
            value = (decimal as NSDecimalNumber).intValue as? T
            rawValue = decimal
        } else if let string = try? container.decode(String.self) {
            value = Int(string) as? T
            rawValue = string
        } else if let bool = try? container.decode(Bool.self) {
            value = (bool ? 1 : 0) as? T
            rawValue = bool
        }
    } else if T.self == Decimal.self {
        if let string = try? container.decode(String.self) {
            value = Decimal(string: string) as? T
            rawValue = string
        }
    } else if T.self == Double.self {
        if let string = try? container.decode(String.self) {
            value = Double(string) as? T
            rawValue = string
        }
    } else if T.self == String.self {
        if let int = try? container.decode(Int.self) {
            value = "\(int)" as? T
            rawValue = int
        } else if let decimal = try? container.decode(Decimal.self) {
            value = "\(decimal)" as? T
            rawValue = decimal
        } else if let bool = try? container.decode(Bool.self) {
            value = "\(bool)" as? T
            rawValue = bool
        }
    } else if T.self == Bool.self {
        if let string = try? container.decode(String.self) {
            value = ["true", "y", "t", "yes", "1"].contains { string.caseInsensitiveCompare($0) == .orderedSame } as? T
            rawValue = string
        } else if let int = try? container.decode(Int.self) {
            if int == 1 {
                value = true as? T
                rawValue = int
            } else if int == 0 {
                value = false as? T
                rawValue = int
            }
        }
    }
    if nil == value {
        throw DecodingError.typeMismatch(T.self, DecodingError.Context.init(codingPath: container.codingPath, debugDescription: "tryMakeWrapperValue failed"))
    }
    return value
}

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

public protocol Initializable {
    init()
}

extension NSObject: Initializable {}
extension String: Initializable {}
extension Int: Initializable {}
extension Double: Initializable {}
extension Bool: Initializable {}
extension Dictionary: Initializable {}
extension Array: Initializable {}
extension Set: Initializable {}

public struct DefaultValueProviders {
    
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
        public static let `default` = Decimal.zero
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
    
    public enum Init<A>: DefaultValueProvider where A: Initializable & Codable {
        public static var `default`: A  { A() }
    }
}

public struct Default {
    
    public typealias BoolFalse = DefaultValue<DefaultValueProviders.BoolFalse>
    public typealias BoolTrue = DefaultValue<DefaultValueProviders.BoolTrue>
    public typealias IntZero = DefaultValue<DefaultValueProviders.IntZero>
    public typealias DoubleZero = DefaultValue<DefaultValueProviders.DoubleZero>
    public typealias DecimalZero = DefaultValue<DefaultValueProviders.DecimalZero>
    public typealias StringEmpty = DefaultValue<DefaultValueProviders.StringEmpty>
    public typealias ArrayEmpty<A: Codable & RangeReplaceableCollection> = DefaultValue<DefaultValueProviders.ArrayEmpty<A>>
    public typealias DicEmpty<K: Hashable & Codable, V: Codable> = DefaultValue<DefaultValueProviders.DicEmpty<K, V>>
    public typealias CaseFirst<A: Codable & CaseIterable> = DefaultValue<DefaultValueProviders.CaseFirst<A>>
}

