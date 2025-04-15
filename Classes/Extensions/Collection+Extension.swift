//
//  Collection+Extension.swift
//  ADKit
//
//  Created by ray on 2025/2/14.
//

import CommonCrypto

extension String {
    
    public var sha1: String {
        let data = Data(self.utf8)
        var digest = [UInt8](repeating: 0, count:Int(CC_SHA1_DIGEST_LENGTH))
        data.withUnsafeBytes {
            _ = CC_SHA1($0.baseAddress, CC_LONG(data.count), &digest)
        }
        let hexBytes = digest.map { String(format: "%02hhx", $0) }
        return hexBytes.joined()
    }
}

extension Dictionary where Key == String, Value == String {
    
    public var sha1: String {
        sortedURLParams.sha1
    }
    
    public var sortedURLParams: String {
        let sortedKeys = self.keys.sorted()
        let str = sortedKeys.map { key in
            let value = self[key] ?? ""
            return "\(key)=\(value)"
        }.joined(separator: "&")
        return str
    }
}

extension Array where Element == String {
    
    public var sha1: String {
        sortedJoined(separator: ",").sha1
    }
    
    public func sortedJoined(separator: String) -> String {
        sorted().joined(separator: separator)
    }
}


extension Dictionary {
    
    public subscript<T: SingleValueConvertable>(_ convertor: (key: Key, type: T.Type)) -> T? {
        guard let value = self[convertor.key] else {
            return nil
        }
        return convert(value: value, toType: T.self)
    }
    
    public subscript(_ convertor: (key: Key, type: [String: Any].Type)) -> [String: Any]? {
        guard let value = self[convertor.key] else {
            return nil
        }
        return value as? [String: Any]
    }
    
    public subscript(_ convertor: (key: Key, type: [Any].Type)) -> [Any]? {
        guard let value = self[convertor.key] else {
            return nil
        }
        return value as? [Any]
    }
    
    public func mapValuesByConvertingTo<T: SingleValueConvertable>(_ type: T.Type) -> [Key: T?] {
        mapValues {
            convert(value: $0, toType: type)
        }
    }
    
    public func compactMapValuesByConvertingTo<T: SingleValueConvertable>(_ type: T.Type) -> [Key: T] {
        compactMapValues {
            convert(value: $0, toType: type)
        }
    }
}


extension Array {
    
    public subscript<T: SingleValueConvertable>(_ convertor: (index: Index, type: T.Type)) -> T? {
        let index = convertor.index
        if index < 0 || index >= count {
            return nil
        }
        let value = self[index]
        return convert(value: value, toType: T.self)
    }
    
    public subscript(_ convertor: (index: Index, type: [String: Any].Type)) -> [String: Any]? {
        let index = convertor.index
        if index < 0 || index >= count {
            return nil
        }
        let value = self[index]
        return value as? [String: Any]
    }
    
    public subscript(_ convertor: (index: Index, type: [Any].Type)) -> [Any]? {
        let index = convertor.index
        if index < 0 || index >= count {
            return nil
        }
        let value = self[index]
        return value as? [Any]
    }
    
    public func mapByConvertingTo<T: SingleValueConvertable>(_ type: T.Type) -> [T?] {
        map {
            convert(value: $0, toType: type)
        }
    }
    
    public func compactMapByConvertingTo<T: SingleValueConvertable>(_ type: T.Type) -> [T] {
        compactMap {
            convert(value: $0, toType: type)
        }
    }
}
