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
        String(describing: wrappedValue)
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
    if toType == Float.self {
        return value.convertToFloat() as? T
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
    rawValue = nil
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
            } else if T.self == [Float].self {
                value = array.compactMap {
                    convert(value: $0, toType:Float.self)
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
            } else if T.self == [String: Float].self {
                value = dic.compactMapValues {
                    convert(value: $0, toType:Float.self)
                } as? T
            } else if T.self == [String: String].self {
                value = dic.compactMapValues {
                    convert(value: $0, toType:String.self)
                } as? T
            }
        }
    } else {
        if let single = try? container.decode(SingleValue.self), let raw = single.raw {
            rawValue = raw
            if T.self == Int.self {
                value = single.value(Int.self) as? T
            } else if T.self == Decimal.self {
                value = single.value(Decimal.self) as? T
            } else if T.self == Double.self {
                value = single.value(Double.self) as? T
            } else if T.self == Float.self {
                value = single.value(Float.self) as? T
            } else if T.self == String.self {
                value = single.value(String.self) as? T
            } else if T.self == Bool.self {
                value = single.value(Bool.self) as? T
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

public protocol ZeroValue {
    static var zeroValue: Self { get }
}

public protocol EmptyValue {
    static var emptyValue: Self { get }
}

public extension ZeroValue where Self: Numeric {
    static var zeroValue: Self { .zero }
}

public extension EmptyValue where Self: RangeReplaceableCollection {
    static var emptyValue: Self { Self() }
}

extension String: Initializable {}
extension String: EmptyValue {}
extension Int: Initializable {}
extension Int: ZeroValue {}
extension Double: Initializable {}
extension Double: ZeroValue {}
extension Float: Initializable {}
extension Float: ZeroValue {}
extension Decimal: ZeroValue {}
extension Bool: Initializable {}
extension Dictionary: Initializable {}
extension Dictionary: EmptyValue {
    public static var emptyValue: [Key: Value] { [:] }
}
extension Array: Initializable {}
extension Array: EmptyValue {}
extension Set: Initializable {}
extension Set: EmptyValue {
    public static var emptyValue: Set<Element> { [] }
}

public struct DefaultValueProviders {

    public enum BoolFalse: DefaultValueProvider {
        public static let `default` = false
    }

    public enum BoolTrue: DefaultValueProvider {
        public static let `default` = true
    }

    public enum CaseFirst<A>: DefaultValueProvider where A: Codable & CaseIterable {
        public static var `default`: A { A.allCases.first! }
    }

    public enum Init<A>: DefaultValueProvider where A: Initializable & Codable {
        public static var `default`: A  { A() }
    }

    public enum InitObject<A>: DefaultValueProvider where A: NSObject & Codable {
        public static var `default`: A  { A() }
    }
}

public enum ZeroProvider<T: Codable & ZeroValue>: DefaultValueProvider {
    public static var `default`: T { T.zeroValue }
}

public enum EmptyProvider<T: Codable & EmptyValue>: DefaultValueProvider {
    public static var `default`: T { T.emptyValue }
}

public struct Default {

    public typealias Zero<T: Codable & ZeroValue> = DefaultValue<ZeroProvider<T>>
    public typealias Empty<T: Codable & EmptyValue> = DefaultValue<EmptyProvider<T>>
    public typealias False = DefaultValue<DefaultValueProviders.BoolFalse>
    public typealias True = DefaultValue<DefaultValueProviders.BoolTrue>
    public typealias CaseFirst<A: Codable & CaseIterable> = DefaultValue<DefaultValueProviders.CaseFirst<A>>

    @available(*, deprecated, message: "Use @Default.Zero instead.")
    public typealias IntZero = Zero<Int>
    @available(*, deprecated, message: "Use @Default.Zero instead.")
    public typealias DoubleZero = Zero<Double>
    @available(*, deprecated, message: "Use @Default.Zero instead.")
    public typealias FloatZero = Zero<Float>
    @available(*, deprecated, message: "Use @Default.Zero instead.")
    public typealias DecimalZero = Zero<Decimal>

    @available(*, deprecated, message: "Use @Default.False instead.")
    public typealias BoolFalse = DefaultValue<DefaultValueProviders.BoolFalse>
    @available(*, deprecated, message: "Use @Default.True instead.")
    public typealias BoolTrue = DefaultValue<DefaultValueProviders.BoolTrue>

    @available(*, deprecated, message: "Use @Default.Empty instead.")
    public typealias StringEmpty = Empty<String>
    @available(*, deprecated, message: "Use @Default.Empty instead.")
    public typealias ArrayEmpty<A: Codable & RangeReplaceableCollection & EmptyValue> = Empty<A>
    @available(*, deprecated, message: "Use @Default.Empty instead.")
    public typealias DicEmpty<K: Hashable & Codable, V: Codable> = Empty<[K: V]>
    @available(*, deprecated, message: "Use @Default.Empty instead.")
    public typealias SetEmpty<A: Hashable & Codable> = Empty<Set<A>>
}


public protocol SingleValueConvertable {
    func convertToInt() -> Int?
    func convertToDecimal() -> Decimal?
    func convertToString() -> String?
    func convertToDouble() -> Double?
    func convertToFloat() -> Float?
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

    public func convertToFloat() -> Float? {
        Float(self)
    }

    public func convertToBool() -> Bool? {
        self == 0 ? false : (self == 1 ? true : nil)
    }
}

extension Decimal: SingleValueConvertable {
    public func convertToInt() -> Int? {
        guard isNormal else {
            return nil
        }
        return Int((self as NSDecimalNumber).doubleValue)
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

    public func convertToFloat() -> Float? {
        Float((self as NSDecimalNumber).doubleValue)
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

    public func convertToFloat() -> Float? {
        Float(self)
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

    public func convertToFloat() -> Float? {
        Float(self)
    }

    public func convertToBool() -> Bool? {
        self == 1 ? true : (self == 0 ? false : nil)
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
        self ? 1.0 : 0.0
    }

    public func convertToFloat() -> Float? {
        self ? 1.0 : 0.0
    }

    public func convertToBool() -> Bool? {
        self
    }
}
extension Float: SingleValueConvertable {

    public func convertToInt() -> Int? {
        Int(self)
    }

    public func convertToDecimal() -> Decimal? {
        Decimal(Double(self))
    }

    public func convertToString() -> String? {
        "\(self)"
    }

    public func convertToDouble() -> Double? {
        Double(self)
    }

    public func convertToFloat() -> Float? {
        self
    }

    public func convertToBool() -> Bool? {
        self == 1 ? true : (self == 0 ? false : nil)
    }
}


public struct SingleValue: Codable {
    /// Int, Decimal, String, Bool, Double
    public let raw: (any SingleValueConvertable)?
    
    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        if let raw = raw as? Encodable {
            try container.encode(raw)
        } else {
            try container.encodeNil()
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
        } else if let value = try? container.decode(Double.self) {
            raw = value
        } else {
            raw = nil
        }
    }
    
    public init(_ raw: Any?) {
        guard let raw else {
            self.raw = nil
            return
        }
        var convertedRaw: (any SingleValueConvertable)?
        let value = raw
        switch value {
        case let value as any StringProtocol:
            convertedRaw = "\(value)"
        case let value as any Numeric:
            if value is any BinaryInteger, let int = Int("\(value)") {
                convertedRaw = int
            } else if value is Decimal {
                convertedRaw = value as! Decimal
            } else if value is any FloatingPoint, let double = Double("\(value)") {
                convertedRaw = double
            }
        case let value as NSNumber:
            if value is NSDecimalNumber {
                convertedRaw = value.decimalValue
            } else if value === kCFBooleanTrue || value === kCFBooleanFalse {
                convertedRaw = value.boolValue
            } else if value.decimalValue == Decimal(value.intValue) {
                convertedRaw = value.intValue
            }
        case let value as Bool:
            convertedRaw = value
        default:
            break
        }
        self.raw = convertedRaw
    }
}
