//
//  Decodable+Extension.swift
//  ADKit
//
//  Created by ray on 2025/2/14.
//

import Foundation

public extension Decodable {
    
    init?(fromJsonData data: Data, decoder: JSONDecoder = JSONDecoder()) {
        do {
            let res = try decoder.decode(Self.self, from: data)
            self = res
            return
        } catch let e {
            debugPrint("Decodable.fromJsonData Error: \(e)")
        }
        debugPrint("Decodable.fromJsonData: try parse from empty {}")
        var data = "{}".data(using: .utf8)!
        if let res = try? decoder.decode(Self.self, from: data) {
            self = res
            return
        }
        debugPrint("Decodable.fromJsonData: try parse from empty []")
        data = "[]".data(using: .utf8)!
        if let res = try? decoder.decode(Self.self, from: data) {
            self = res
            return
        }
        return nil
    }
    
    init?(fromJsonString jsonString: String, decoder: JSONDecoder = JSONDecoder()) {
        if let data = jsonString.data(using: .utf8) {
            do {
                self = try decoder.decode(Self.self, from: data)
                return
            } catch let e {
                debugPrint("Decodable.fromJsonString Error: \(e)")
            }
        }
        self.init(fromJsonData: Data(), decoder: decoder)
    }
    
    init?(fromJsonDic dic: [String: Any], decoder: JSONDecoder = JSONDecoder()) {
        do {
            let data = try JSONSerialization.data(withJSONObject: dic)
            self = try decoder.decode(Self.self, from: data)
        } catch let e {
            debugPrint("Decodable.fromDictionary Error: \(e)")
        }
        self.init(fromJsonData: Data(), decoder: decoder)
    }
}

// 使Decodable而不具Encodable的obj能直接打印
public protocol JsonDebugStringConvertable: CustomDebugStringConvertible {
    var debugDescription: String { get }
}

public extension JsonDebugStringConvertable {
    private static func convertToJsonValue(_ value: Any) -> Any? {
        let mirror = Mirror(reflecting: value)
        // 处理Optional
        if mirror.displayStyle == .optional {
            guard let firstChild = mirror.children.first else {
                return NSNull() // 显式返回null而不是nil
            }
            return convertToJsonValue(firstChild.value)
        }
        // 处理DefaultValue类型
        let typeName = String(describing: type(of: value))
        if typeName.starts(with: "DefaultValue<") {
            if let wrappedValue = mirror.children.first(where: { $0.label == "wrappedValue" }) {
                return convertToJsonValue(wrappedValue.value)
            }
        }
        // 处理基础类型
        if mirror.children.isEmpty {
            return value
        }
        // 处理Array
        if let array = value as? [Any] {
            return array.map { convertToJsonValue($0) ?? NSNull() }
        }
        // 处理Dictionary
        if let dict = value as? [AnyHashable: Any] {
            var result = [String: Any]()
            for (key, value) in dict {
                if let strKey = key as? String {
                    result[strKey] = convertToJsonValue(value) ?? NSNull()
                }
            }
            return result
        }
        // 处理普通对象
        var result = [String: Any]()
        for child in mirror.children {
            guard let label = child.label else { continue }
            result[label] = convertToJsonValue(child.value) ?? NSNull()
        }
        return result
    }
    
    var debugDescription: String {
        #if DEBUG
        let jsonValue = Self.convertToJsonValue(self)
        if let jsonData = try? JSONSerialization.data(withJSONObject: jsonValue ?? [:]),
           let jsonString = String(data: jsonData, encoding: .utf8) {
            return "\(Self.self): \(jsonString)"
        }
        return "\(Self.self): {}"
        #else
        return ""
        #endif
    }
}

