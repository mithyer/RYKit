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

extension Swift.Optional where Wrapped == String {
    mutating func callIfNil(_ call: (inout Self) -> Void) {
        if nil == self {
            call(&self)
        }
    }
}
