//
//  Collection+Extension.swift
//  ADKit
//
//  Created by ray on 2025/2/14.
//

import CommonCrypto

extension String {
    
    var sha1: String {
        
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
    
    var sha1: String {
        
        let str = sortedURLParams
        let data = Data(str.utf8)
        var digest = [UInt8](repeating: 0, count: Int(CC_SHA1_DIGEST_LENGTH))
        _ = data.withUnsafeBytes { buffer in
            CC_SHA1(buffer.baseAddress, CC_LONG(data.count), &digest)
        }
        return digest.map { String(format: "%02hhx", $0) }.joined()
    }
    
    var sortedURLParams: String {
        
        let sortedKeys = self.keys.sorted()
        let str = sortedKeys.map { key in
            let value = self[key] ?? ""
            return "\(key)=\(value)"
        }.joined(separator: "&")
        return str
    }
}
