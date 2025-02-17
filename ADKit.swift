//
//  ADKit.swift
//  ADKit
//
//  Created by ray on 2025/2/17.
//


public class ADKit {
    
    public static var version: String {
        guard let dictionary = Bundle.init(for: ADKit.self).infoDictionary else {
            return "unknown"
        }
        let version = dictionary["CFBundleShortVersionString"] as? String
        return version ?? "unknown"
    }

}

