//
//  CollectionValue.swift
//  RYKit
//
//  Created by mao rui on 2026/4/3.
//

public protocol AnyCollectionValue {}
extension [Any]: AnyCollectionValue {}
extension [String: Any]: AnyCollectionValue {}

@propertyWrapper
public struct CollectionValue<T: AnyCollectionValue>: Codable, CustomStringConvertible {
    public var wrappedValue: T?

    public var description: String {
        String(describing: wrappedValue)
    }

    public init() {
        wrappedValue = nil
    }

    public init(wrappedValue: T?) {
        self.wrappedValue = wrappedValue
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            wrappedValue = nil
        // Bridge `[Any]` via CodableArray because `Any` is not directly Codable.
        } else if T.self == [Any].self,
                  let array = try? container.decode(CodableArray.self).array as? T {
            wrappedValue = array
        // Bridge `[String: Any]` via CodableDictionary for the same reason.
        } else if T.self == [String: Any].self,
                  let dictionary = try? container.decode(CodableDictionary.self).dictionary as? T {
            wrappedValue = dictionary
        } else {
            // Fail-soft by design: mismatched payloads decode to nil instead of throwing.
            wrappedValue = nil
        }
    }

    public func encode(to encoder: any Encoder) throws {
        guard let wrappedValue else {
            return
        }

        var container = encoder.singleValueContainer()
        if let array = wrappedValue as? [Any] {
            try container.encode(CodableArray(array))
        } else if let dictionary = wrappedValue as? [String: Any] {
            try container.encode(CodableDictionary(dictionary))
        }
    }
}

public extension KeyedDecodingContainer {
    func decode<T>(_ type: CollectionValue<T>.Type, forKey key: K) throws -> CollectionValue<T> {
        // Keep wrapper behavior consistent with other wrappers: missing key -> nil wrapped value.
        try decodeIfPresent(type, forKey: key) ?? .init()
    }
}

public extension KeyedEncodingContainer {
    mutating func encode<T>(_ value: CollectionValue<T>, forKey key: Key) throws {
        // Omit key when wrapped value is nil.
        guard let wrappedValue = value.wrappedValue else {
            return
        }

        if let array = wrappedValue as? [Any] {
            try encode(array, forKey: key)
        } else if let dictionary = wrappedValue as? [String: Any] {
            try encode(dictionary, forKey: key)
        }
    }
}
