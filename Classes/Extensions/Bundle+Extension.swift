//
//  Bundle.swift
//  Pods
//
//  Created by ray on 2025/2/14.
//

import Foundation

extension RYObject where T: Bundle {
    
    public var buildDate: Date? {
        if let infoPath = refer.path(forResource: "Info", ofType: "plist"),
           let attributes = try? FileManager.default.attributesOfItem(atPath: infoPath) {
            return attributes[.modificationDate] as? Date
        }
        return nil
    }
    
    public var buildDateString: String? {
        if let date = buildDate {
            let formatter = DateFormatter()
            formatter.dateFormat = "yyMMddHHmmss"
            return formatter.string(from: date)
        }
        return nil
    }
}
