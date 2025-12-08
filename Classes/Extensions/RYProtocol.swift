//
//  RYExtension.swift
//  RYKit
//
//  Created by mao rui on 2025/12/8.
//

import Foundation

public struct RYObject<T> {
    var refer: T
    init(_ refer: T) {
        self.refer = refer
    }
}

public protocol RYProtocol {
    associatedtype T
    var ry: RYObject<T> { get }
    static var ry: RYObject<T>.Type { get }
}

public extension RYProtocol {
    
    var ry: RYObject<Self> {
        RYObject<Self>(self)
    }
    
    static var ry: RYObject<Self>.Type {
        RYObject<Self>.self
    }
}

extension NSObject: RYProtocol {}
