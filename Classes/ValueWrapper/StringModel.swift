//
//  StringModel.swift
//  Pods
//
//  Created by ray on 2025/6/4.
//

import Foundation

@propertyWrapper
public struct StringModel<T: Codable>: Codable, CustomStringConvertible {
    
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
    
    public init() {}
    
    public init(wrappedValue: T?) {
        self.wrappedValue = wrappedValue
    }
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        do {
            if let model = try? container.decode(T.self) {
                self.wrappedValue = model
                return
            }
            guard let string = try? container.decode(String.self) else {
                throw DecodingError.valueNotFound(String.self, DecodingError.Context.init(codingPath: container.codingPath, debugDescription: "It's not a string value"))
            }
            guard let t = T.init(fromJsonString: string) else {
                throw DecodingError.valueNotFound(T.self, DecodingError.Context.init(codingPath: container.codingPath, debugDescription: "Convert from string failed: \(string)"))
            }
            rawValue = string
            self.wrappedValue = t
        } catch let e {
            debugPrint(e)
        }
    }
    
    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        if let string = rawValue as? String {
            try container.encode(string)
        } else if let wrappedValue {
            try container.encode(wrappedValue)
        }
    }
}
