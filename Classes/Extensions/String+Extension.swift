//
//  Bundle.swift
//  Pods
//
//  Created by ray on 2025/2/14.
//

public extension String {
    
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
