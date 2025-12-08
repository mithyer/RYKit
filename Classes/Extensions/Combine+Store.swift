//
//  Combine+More.swift
//  Device
//
//  Created by mao rui on 2025/11/28.
//

import Foundation
import Combine

fileprivate extension Associatable where Self: AnyObject {
    
    var cancellableDic: [String: AnyCancellable] {
        get {
            associated(#function, initializer: [String: AnyCancellable]())!
        }
        set {
            setAssociated(#function, value: newValue)
        }
    }
}

extension AnyCancellable {
    
    // attach to instance
    public func store<T: AnyObject & Associatable>(to obj: T, with key: String? = nil, doNotStoreIfHasSameKey: Bool = false) {
        if doNotStoreIfHasSameKey, let key, nil != obj.cancellableDic[key] {
            return
        }
        let key = key ?? UUID().uuidString
        obj.cancellableDic[key] = self
    }
    
    private static var classToCancelationDic = [String: [String: AnyCancellable]]()
    
    // attach to class
    public func store<T: AnyObject>(to classType: T.Type, with key: String? = nil, doNotStoreIfHasSameKey: Bool = false) {
        if doNotStoreIfHasSameKey, let key, nil != Self.classToCancelationDic["\(classType)"]?[key] {
            return
        }
        var cancelationDic = Self.classToCancelationDic["\(classType)"] ?? [String: AnyCancellable]()
        cancelationDic[key ?? UUID().uuidString] = self
        Self.classToCancelationDic["\(classType)"] = cancelationDic
    }
}
