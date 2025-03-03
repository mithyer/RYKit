//
//  Capables.swift
//  ADKit
//
//  Created by ray on 2025/2/14.
//

import Foundation

fileprivate var associatedDictionaryKey: Int = 0

public protocol Associatable {
    
    func associated<T>(_ key: String, initializer: @autoclosure () -> T?) -> T?
    func setAssociated<T>(_ key: String, value: T?)
}

fileprivate class Wrapper<T> {
    var v: T?
    init(_ t: T?) {
        self.v = t
    }
}

extension Associatable {
    
    fileprivate var associatedDictionary: NSMutableDictionary {
        get {
            var dic = objc_getAssociatedObject(self, &associatedDictionaryKey) as? NSMutableDictionary
            if nil == dic {
                dic = NSMutableDictionary()
                objc_setAssociatedObject(self, &associatedDictionaryKey, dic, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
            }
            return dic!
        }
    }
    
    public func associated<T>(_ key: String = "\(T.self)", initializer: @autoclosure () -> T?) -> T? {
        let dic = associatedDictionary
        var wrapper = dic[key] as? Wrapper<T>
        if nil == wrapper {
            wrapper = Wrapper(initializer())
            dic[key] = wrapper!
        }
        return wrapper!.v
    }
    
    public func setAssociated<T>(_ key: String = "\(T.self)", value: T?) {
        let dic = associatedDictionary
        if let wrapper = dic[key] as? Wrapper<T> {
            wrapper.v = value
        } else {
            dic[key] = Wrapper(value)
        }
    }
}
