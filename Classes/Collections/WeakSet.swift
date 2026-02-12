//
//  WeakSet.swift
//  RYKit
//
//  Created by mao rui on 2026/2/11.
//

public class WeakBoxOfSet<Key: Hashable & Equatable & AnyObject>: WeakBoxProtocol {
    
    public weak var value: Key?
    public weak var key: Key?
    public let hashValue: Int
    public required init(key: Key, value: Key) {
        self.value = key
        self.key = key
        self.hashValue = key.hashValue
    }
}

public class WeakSet<Element: AnyObject & Hashable & Equatable>: _WeakMap<WeakBoxOfSet<Element>> {
    
    @available(*, unavailable)
    public override func insert(key: _WeakMap<WeakBoxOfSet<Element>>.Key, _ element: _WeakMap<WeakBoxOfSet<Element>>.Element) {
        super.insert(key: key, element)
    }
    
    @available(*, unavailable)
    public override func allKeys() -> [_WeakMap<WeakBoxOfSet<Element>>.Key] {
        super.allKeys()
    }
    
    @available(*, unavailable)
    public override func allValues() -> [_WeakMap<WeakBoxOfSet<Element>>.Element] {
        super.allValues()
    }
    
    public func insert(_ element: _WeakMap<WeakBoxOfSet<Element>>.Element) {
        super.insert(key: element, element)
    }
    
    public override func remove(_ element: _WeakMap<WeakBoxOfSet<Element>>.Key) -> _WeakMap<WeakBoxOfSet<Element>>.Element? {
        super.remove(element)
    }
    
    public override func contains(_ element: _WeakMap<WeakBoxOfSet<Element>>.Key) -> Bool {
        super.contains(element)
    }
    
    public func allElements() -> [_WeakMap<WeakBoxOfSet<Element>>.Element] {
        super.allKeys()
    }
}
