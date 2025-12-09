//
//  EventCenter+Print.swift
//  RYKit
//
//  Created by ray on 2025/12/9.
//

import Foundation

extension EventCenter {
    
    public enum PrintType {
        case allEventTypes
        case allOneToOneEventTypes
        case allOneToManyEventTypes
        case boundEventTypes(of: EventBindable)
    }
    
    public func printContext(_ printType: PrintType) {
        switch printType {
        case .allEventTypes:
            eventHanldersDic.forEach { (key, _) in
                print(key)
            }
        case .allOneToOneEventTypes:
            eventHanldersDic.filter {
                if case .oneToOne = $0.key {
                    return true
                }
                return false
            }.forEach { (key, _) in
                print(key)
            }
        case .allOneToManyEventTypes:
            eventHanldersDic.filter {
                if case .oneToMany = $0.key {
                    return true
                }
                return false
            }.forEach { (key, _) in
                print(key)
            }
        case .boundEventTypes(let of):
            of.boundEventTypes.sorted { l, r in
                if l.order == r.order {
                    return l.inside < r.inside
                }
                return l.order < r.order
            }.forEach {
                print($0)
            }
            
        }
    }
    
}
