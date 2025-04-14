//
//  DefaultValue.swift
//  TRSTradingClient
//
//  Created by ray on 2025/2/9.
//

// Decode时将非Optional的值设置默认值，并且会尝试将其他类型值转换为已声明类型，避免不存在该键值时throw error

import Foundation

@propertyWrapper
public struct DefaultValue<Provider: DefaultValueProvider>: Codable, CustomStringConvertible {
    
    public var wrappedValue: Provider.Value
    private var useDefaultValue = true
    private var rawValue: Any?
    
    enum CodingKeys: CodingKey {
        case wrappedValue
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

private protocol ArrayType {}
extension Array: ArrayType {}
private protocol DicType {}
extension Dictionary: DicType {}

func convert<T: SingleValueConvertable>(value: Any, toType: T.Type) -> T? {
    if value is T {
        return value as? T
    }
    guard let value = value as? any SingleValueConvertable else {
        return nil
    }
    if toType == Int.self {
        return value.convertToInt() as? T
    }
    if toType == Decimal.self {
        return value.convertToDecimal() as? T
    }
    if toType == Double.self {
        return value.convertToDouble() as? T
    }
    if toType == String.self {
        return value.convertToString() as? T
    }
    if toType == Bool.self {
        return value.convertToBool() as? T
    }
    return nil
}

func tryMakeWrapperValue<T: Decodable>(container: any SingleValueDecodingContainer, rawValue: inout Any?) throws -> T? {
    if container.decodeNil() {
        return nil
    }
    var value = try? container.decode(T.self)
    if nil != value {
        return value
    }
    if T.self is ArrayType.Type {
        if let array = try? container.decode(CodableArray.self).array {
            rawValue = array
            if T.self == [Int].self {
                value = array.compactMap {
                    convert(value: $0, toType:Int.self)
                } as? T
            } else if T.self == [Decimal].self {
                value = array.compactMap {
                    convert(value: $0, toType:Decimal.self)
                } as? T
            } else if T.self == [Double].self {
                value = array.compactMap {
                    convert(value: $0, toType:Double.self)
                } as? T
            } else if T.self == [String].self {
                value = array.compactMap {
                    convert(value: $0, toType:String.self)
                } as? T
            }
        }
    } else if T.self is DicType.Type {
        if let dic = try? container.decode(CodableDictionary.self).dictionary {
            rawValue = dic
            if T.self == [String: Int].self {
                value = dic.compactMapValues {
                    convert(value: $0, toType:Int.self)
                } as? T
            } else if T.self == [String: Decimal].self {
                value = dic.compactMapValues {
                    convert(value: $0, toType:Decimal.self)
                } as? T
            } else if T.self == [String: Double].self {
                value = dic.compactMapValues {
                    convert(value: $0, toType:Double.self)
                } as? T
            } else if T.self == [String: String].self {
                value = dic.compactMapValues {
                    convert(value: $0, toType:String.self)
                } as? T
            }
        }
    } else {
        if T.self == Int.self {
            if let decimal = try? container.decode(Decimal.self) {
                value = decimal.convertToInt() as? T
                rawValue = decimal
            } else if let string = try? container.decode(String.self) {
                value = string.convertToInt() as? T
                rawValue = string
            } else if let bool = try? container.decode(Bool.self) {
                value = bool.convertToInt() as? T
                rawValue = bool
            }
        } else if T.self == Decimal.self {
            if let string = try? container.decode(String.self) {
                value = string.convertToDecimal() as? T
                rawValue = string
            }
        } else if T.self == Double.self {
            if let string = try? container.decode(String.self) {
                value = string.convertToDouble() as? T
                rawValue = string
            }
        } else if T.self == String.self {
            if let int = try? container.decode(Int.self) {
                value = int.convertToString() as? T
                rawValue = int
            } else if let decimal = try? container.decode(Decimal.self) {
                value = decimal.convertToString() as? T
                rawValue = decimal
            } else if let bool = try? container.decode(Bool.self) {
                value = bool.convertToString() as? T
                rawValue = bool
            }
        } else if T.self == Bool.self {
            if let string = try? container.decode(String.self) {
                value = string.convertToBool() as? T
                rawValue = string
            } else if let int = try? container.decode(Int.self) {
                value = int.convertToBool() as? T
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


public protocol SingleValueConvertable {
    func convertToInt() -> Int?
    func convertToDecimal() -> Decimal?
    func convertToString() -> String?
    func convertToDouble() -> Double?
    func convertToBool() -> Bool?
}

extension Int: SingleValueConvertable {
    public func convertToInt() -> Int? {
        self
    }
    
    public func convertToDecimal() -> Decimal? {
        Decimal(self)
    }
    
    public func convertToString() -> String? {
        "\(self)"
    }
    
    public func convertToDouble() -> Double? {
        Double(self)
    }
    
    public func convertToBool() -> Bool? {
        self == 0 ? false : (self == 1 ? true : nil)
    }
}

extension Decimal: SingleValueConvertable {
    public func convertToInt() -> Int? {
        (self as NSDecimalNumber).intValue
    }
    
    public func convertToDecimal() -> Decimal? {
        self
    }
    
    public func convertToString() -> String? {
        "\(self)"
    }
    
    public func convertToDouble() -> Double? {
    (self as NSDecimalNumber).doubleValue
    }
    
    public func convertToBool() -> Bool? {
        self == 0 ? false : (self == 1 ? true : nil)
    }
}

extension String: SingleValueConvertable {
    
    public func convertToInt() -> Int? {
        Int(self)
    }
    
    public func convertToDecimal() -> Decimal? {
        Decimal(string: self)
    }
    
    public func convertToString() -> String? {
        self
    }
    
    public func convertToDouble() -> Double? {
        Double(self)
    }
    
    public func convertToBool() -> Bool? {
        ["true", "y", "t", "yes", "1"].contains { caseInsensitiveCompare($0) == .orderedSame }
    }
}

extension Double: SingleValueConvertable {
    
    public func convertToInt() -> Int? {
        Int(self)
    }
    
    public func convertToDecimal() -> Decimal? {
        Decimal(self)
    }
    
    public func convertToString() -> String? {
        "\(self)"
    }
    
    public func convertToDouble() -> Double? {
        self
    }
    
    public func convertToBool() -> Bool? {
        nil
    }
}

extension Bool: SingleValueConvertable {
    
    public func convertToInt() -> Int? {
        self ? 1 : 0
    }
    
    public func convertToDecimal() -> Decimal? {
        Decimal(self ? 1 : 0)
    }
    
    public func convertToString() -> String? {
        "\(self)"
    }
    
    public func convertToDouble() -> Double? {
        nil
    }
    
    public func convertToBool() -> Bool? {
        self
    }
}

/// Any Int, Decimal, String, Bool
public struct SingleValue: Codable {
    
    let raw: Any?
    
    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        if let raw = raw as? any Encodable {
            try container.encode(raw)
        }
    }
    
    public func value<T: SingleValueConvertable>(_ type: T.Type) -> T? {
        guard let raw else {
            return nil
        }
        return convert(value: raw, toType: T.self)
    }
    
    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let value = try? container.decode(Bool.self) {
           raw = value
        } else if let value = try? container.decode(Int.self) {
            raw = value
        } else if let value = try? container.decode(Decimal.self) {
            raw = value
        } else if let value = try? container.decode(String.self) {
            raw = value
        } else {
            raw = nil
        }
    }
}
