//
//  Sender&Receiver.swift
//  RYKit
//
//  Created by ray on 2025/12/9.
//

import Foundation

public protocol EventBindable: AnyObject {
    #if DEBUG
    var boundEventTypes: Set<BindEventType> { get set }
    #endif
}
#if DEBUG
public enum BindEventType: Equatable, Hashable {
    case oneToOneSender(String)
    case oneToOneReceiver(String)
    case oneToManySender(String)
    case oneToManyReceiver(String)
    
    var order: Int {
        switch self {
        case .oneToOneSender:
            0
        case .oneToOneReceiver:
            1
        case .oneToManySender:
            2
        case .oneToManyReceiver:
            3
        }
    }
    
    var inside: String {
        switch self {
        case .oneToOneSender(let string):
            string
        case .oneToOneReceiver(let string):
            string
        case .oneToManySender(let string):
            string
        case .oneToManyReceiver(let string):
            string
        }
    }
}

extension EventBindable where Self: Associatable {
    
    var boundEventTypes: Set<BindEventType> {
        get {
            associated(#function, initializer: Set<BindEventType>())!
        }
        set {
            setAssociated(#function, value: newValue)
        }
    }
}
#endif


public protocol OneToOneSender: EventBindable {}
public protocol OneToOneReceiver: EventBindable {}
public protocol OneToManySender: EventBindable {}
public protocol OneToManyReceiver: EventBindable {
    // 若不实现会自动生成唯一UUID
    var oneToManyReceiverId: String { get }
}

extension OneToOneSender {
    
    public func bindSelfAs1To1Sender<T: OneToOneEvent>(_ eventType: T.Type) {
        EventCenter.shared.oneToOne(eventType).bindSender(self)
#if DEBUG
        boundEventTypes.insert(.oneToOneSender("\(T.self)"))
#endif
    }
}

extension OneToOneReceiver {
    
    public func bindSelfAs1To1Receiver<T: OneToOneEvent>(_ eventType: T.Type, handler: @escaping (T) -> Void) {
        EventCenter.shared.oneToOne(eventType).bindReceiver(self, handler: handler)
#if DEBUG
        boundEventTypes.insert(.oneToOneReceiver("\(T.self)"))
#endif
    }
}

extension OneToManySender {
    
    public func bindSelfAs1ToManySender<T: OneToManyEvent>(_ eventType: T.Type) {
        EventCenter.shared.oneToMany(eventType).bindSender(self)
#if DEBUG
        boundEventTypes.insert(.oneToManySender("\(T.self)"))
#endif
    }
}

private var oneToManyReceiverIdKey: Int = 0

extension OneToManyReceiver {
    
    public func addSelfAs1ToManyReceiver<T: OneToManyEvent>(_ eventType: T.Type, handler: @escaping (T) -> Void) {
        EventCenter.shared.oneToMany(eventType).addReceiver(self, handler: handler)
#if DEBUG
        boundEventTypes.insert(.oneToManyReceiver("\(T.self)"))
#endif
    }
    
    public func removeSelfAs1ToManyReceiver<T: OneToManyEvent>(_ eventType: T.Type) {
        EventCenter.shared.oneToMany(eventType).removeReceiver(self)
#if DEBUG
        boundEventTypes.insert(.oneToManyReceiver("\(T.self)"))
#endif
    }
        
    public var oneToManyReceiverId: String {
        var id = objc_getAssociatedObject(self, &oneToManyReceiverIdKey) as? String
        if nil == id {
            id = UUID().uuidString
            objc_setAssociatedObject(self, &oneToManyReceiverIdKey, id!, .OBJC_ASSOCIATION_COPY_NONATOMIC)
        }
        return id!
    }
}

