//
//  RYKit.swift
//  RYKit
//
//  Created by ray on 2025/2/17.
//

import Foundation

public func compareVersion(_ version1: String, _ version2: String) -> Int {
    let v1 = version1.split(separator: ".").map { Int($0) ?? 0 }
    let v2 = version2.split(separator: ".").map { Int($0) ?? 0 }
    
    // 获取最长的长度
    let maxLength = max(v1.count, v2.count)
    
    // 比较每个版本号部分
    for i in 0..<maxLength {
        let num1 = i < v1.count ? v1[i] : 0
        let num2 = i < v2.count ? v2[i] : 0
        
        if num1 > num2 {
            return 1
        } else if num1 < num2 {
            return -1
        }
    }
    
    return 0
}

private class EmptyClass {}

public var version: String {
    guard let dictionary = Bundle(for: EmptyClass.self).infoDictionary else {
        return "unknown"
    }
    let version = dictionary["CFBundleShortVersionString"] as? String
    return version ?? "unknown"
}
