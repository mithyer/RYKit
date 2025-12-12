//
//  Combine+More.swift
//  Device
//
//  Created by ray on 2025/11/28.
//

import Foundation
import Combine

fileprivate extension Associatable where Self: AnyObject {
    
    var cancellableDic: [String: AnyCancellable] {
        get {
            associated(#function, initializer: [String: AnyCancellable]())
        }
        set {
            setAssociated(#function, value: newValue)
        }
    }
}

fileprivate extension AnyCancellable {
    
    // attach to instance
    func store<T: AnyObject & Associatable>(to obj: T, with key: String? = nil, doNotStoreIfHasSameKey: Bool = false) {
        if doNotStoreIfHasSameKey, let key, nil != obj.cancellableDic[key] {
            return
        }
        let key = key ?? UUID().uuidString
        obj.cancellableDic[key] = self
    }
    
    private static var classToCancelationDic = [String: [String: AnyCancellable]]()
    
    // attach to class
    func store<T: AnyObject>(to classType: T.Type, with key: String? = nil, doNotStoreIfHasSameKey: Bool = false) {
        if doNotStoreIfHasSameKey, let key, nil != Self.classToCancelationDic["\(classType)"]?[key] {
            return
        }
        var cancelationDic = Self.classToCancelationDic["\(classType)"] ?? [String: AnyCancellable]()
        cancelationDic[key ?? UUID().uuidString] = self
        Self.classToCancelationDic["\(classType)"] = cancelationDic
    }
}

extension AnyCancellable: RYProtocol {}

public extension RYObject<AnyCancellable> {
    
    func store<K: AnyObject & Associatable>(to obj: K, with key: String? = nil, doNotStoreIfHasSameKey: Bool = false) {
        refer.store(to: obj, with: key, doNotStoreIfHasSameKey: doNotStoreIfHasSameKey)
    }
    
    func store<K: AnyObject>(to classType: K.Type, with key: String? = nil, doNotStoreIfHasSameKey: Bool = false) {
        refer.store(to: classType, with: key, doNotStoreIfHasSameKey: doNotStoreIfHasSameKey)
    }
}

public extension RYObject where T: AnyObject & Associatable {
    
    func removeCancellable(_ key: String) {
        refer.cancellableDic[key]?.cancel()
        refer.cancellableDic.removeValue(forKey: key)
    }
}
