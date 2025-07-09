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
        return nil
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
    
    func checkValidation(_ check: (Self) -> Bool) -> Self? {
        if check(self) {
            return self
        }
        return nil
    }
}

extension Encodable {
    
    public var jsonData: Data? {
        if let jsonData = try? JSONEncoder().encode(self) {
            return jsonData
        }
        return nil
    }
    
    public var jsonString: String? {
        if let jsonData = jsonData,
            let string = String(data: jsonData, encoding: .utf8) {
            return string
        }
        return nil
    }
}

class CodableFromStringWrapper<T: Codable>: Codable {
    
    var obj: T?
    
    func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        if let data = try? JSONEncoder().encode(obj) {
            try container.encode(String(data: data, encoding: .utf8))
        }
    }

    required init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        let str = try container.decode(String.self)
        guard let data = str.data(using: .utf8) else {
            return
        }
        obj = try JSONDecoder().decode(T.self, from: data)
    }
}
