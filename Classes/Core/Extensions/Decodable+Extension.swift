//
//  Decodable+Extension.swift
//  RYKit
//
//  Created by ray on 2025/2/14.
//

import Foundation

public extension Decodable {
    
    init?(fromJsonData data: Data, decoder: JSONDecoder = JSONDecoder()) {
        do {
            self = try decoder.decode(Self.self, from: data)
        } catch let e {
            debugPrint("Decodable.fromJsonData Error: \(e)")
            return nil
        }
    }
    
    init?(fromJsonString jsonString: String, decoder: @autoclosure () -> JSONDecoder = JSONDecoder()) {
        guard let data = jsonString.data(using: .utf8) else {
            return nil
        }
        do {
            self = try decoder().decode(Self.self, from: data)
        } catch let e {
            debugPrint("Decodable.fromJsonString Error: \(e)")
            return nil
        }
    }
    
    init?(fromJsonDic dic: [String: Any], decoder: @autoclosure () -> JSONDecoder = JSONDecoder()) {
        do {
            let data = try JSONSerialization.data(withJSONObject: dic)
            self.init(fromJsonData: data, decoder: decoder())
        } catch let e {
            debugPrint("Decodable.fromDictionary Error: \(e)")
            return nil
        }
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

