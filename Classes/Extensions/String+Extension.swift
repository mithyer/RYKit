//
//  Bundle.swift
//  Pods
//
//  Created by ray on 2025/2/14.
//


public extension Swift.Optional where Wrapped == String {
    func transferIfNil(_ call: () -> String) -> String {
        if let self {
            return self
        }
        return call()
    }
}
