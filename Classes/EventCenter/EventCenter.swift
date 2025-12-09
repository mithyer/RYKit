//
//  EventCenter.swift
//  RYKit
//
//  Created by ray on 2025/12/9.
//

import Foundation

public protocol EventData {}

public protocol Event {
    associatedtype DATA: EventData
    var data: DATA { get }
    var sender: EventBindable? { get }
    var receiver: EventBindable? { get set }
    init(data: DATA, sender: EventBindable)
}

public protocol OneToOneEvent: Event {}
public protocol OneToManyEvent: Event {}

// MARK: - 事件接收者信息
struct EventReceiverHolder {
    weak var receiver: EventBindable?
    let id: String
    
    init(receiver: EventBindable, id: String) {
        self.receiver = receiver
        self.id = id
    }
}

// MARK: - 事件中心
class EventCenter {
        
    static let shared = EventCenter()
    
    enum HandlerKey: Equatable, Hashable {
        case oneToOne(String)
        case oneToMany(String)
    }
    
    private(set) var eventHanldersDic: [HandlerKey: AnyObject] = [:]
    
    // 创建或获取 1对1 事件
    func oneToOne<E: OneToOneEvent>(_ type: E.Type) -> OneToOneEventHandler<E> {
        if let existing = eventHanldersDic[.oneToOne("\(E.self)")] as? OneToOneEventHandler<E> {
            return existing
        }
        
        let event = OneToOneEventHandler<E>()
        eventHanldersDic[.oneToOne("\(E.self)")] = event
        return event
    }
    
    // 创建或获取 1对多 事件
    func oneToMany<E: OneToManyEvent>(_ type: E.Type) -> OneToManyEventHandler<E> {
        if let existing = eventHanldersDic[.oneToMany("\(E.self)")] as? OneToManyEventHandler<E> {
            return existing
        }
        
        let event = OneToManyEventHandler<E>()
        eventHanldersDic[.oneToMany("\(E.self)")] = event
        return event
    }
    
    // 清空所有事件
    func removeAll() {
        eventHanldersDic.removeAll()
    }
}
