//
//  Bundle.swift
//  Pods
//
//  Created by ray on 2025/2/14.
//

extension Numeric {
    public var nilIfZero: Self? {
        self == 0 ? nil : self
    }
}
