//
//  Bundle.swift
//  Pods
//
//  Created by ray on 2025/2/14.
//

public extension Bundle {
    
    @objc var buildDate: Date? {
        if let infoPath = self.path(forResource: "Info", ofType: "plist"),
           let attributes = try? FileManager.default.attributesOfItem(atPath: infoPath) {
            return attributes[.modificationDate] as? Date
        }
        return nil
    }
    
    @objc var buildDateString: String? {
        if let date = buildDate {
            let formatter = DateFormatter()
            formatter.dateFormat = "yyMMddHHmmss"
            return formatter.string(from: date)
        }
        return nil
    }
}
