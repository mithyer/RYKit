//
//  Capables.swift
//  ADKit
//
//  Created by ray on 2025/2/14.
//

import Foundation

fileprivate var associatedDictionaryKey: () = ()

public protocol Associatable {
    
    func associated<T>(_ key: String, initilizer: () -> T) -> T
}


extension Associatable {
    
    fileprivate var associatedDictionary: NSMutableDictionary {
        get {
            var dic = objc_getAssociatedObject(self, &associatedDictionaryKey) as? NSMutableDictionary
            if nil == dic {
                dic = NSMutableDictionary()
                objc_setAssociatedObject(dic!, &associatedDictionaryKey, dic, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
            }
            return dic!
        }
    }
    
    public func associated<T>(_ key: String = "\(T.self)", initilizer: () -> T) -> T {
        let dic = associatedDictionary
        let key = "\(T.self)"
        var t = dic[key] as? T
        if nil == t {
            t = initilizer()
            dic[key] = t
        }
        return t!
    }

}
