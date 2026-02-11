//
//  WeakSet.swift
//  RYKit
//
//  Created by mao rui on 2026/2/11.
//

public class WeakBoxOfSet<Key: Hashable & Equatable & AnyObject, Element: Hashable & Equatable & AnyObject>: WeakBoxProtocol {
    
    public weak var value: Element?
    public weak var key: Key?
    public let hashValue: Int
    public required init(key: Key, value: Element) {
        self.value = value
        self.key = key
        self.hashValue = key.hashValue
    }
}

public class WeakSet<Element: AnyObject & Hashable & Equatable>: _WeakMap<WeakBoxOfSet<Element, Element>> {
    
    @available(iOS, obsoleted: 1.0)
    public override func insert(key: _WeakMap<WeakBoxOfSet<Element, Element>>.Key, _ element: _WeakMap<WeakBoxOfSet<Element, Element>>.Element) {
        if key != element {
            fatalError("key should equal to element in WeakSet")
        }
        super.insert(key: key, element)
    }
    
    @available(iOS, obsoleted: 1.0)
    public override func allKeys() -> [_WeakMap<WeakBoxOfSet<Element, Element>>.Key] {
        super.allKeys()
    }
    
    @available(iOS, obsoleted: 1.0)
    public override func allValues() -> [_WeakMap<WeakBoxOfSet<Element, Element>>.Element] {
        super.allValues()
    }
    
    public func insert(_ element: _WeakMap<WeakBoxOfSet<Element, Element>>.Element) {
        super.insert(key: element, element)
    }
    
    public override func remove(_ element: _WeakMap<WeakBoxOfSet<Element, Element>>.Key) -> _WeakMap<WeakBoxOfSet<Element, Element>>.Element? {
        super.remove(element)
    }
    
    public override func contains(_ element: _WeakMap<WeakBoxOfSet<Element, Element>>.Key) -> Bool {
        super.contains(element)
    }
    

    
    public func allElements() -> [_WeakMap<WeakBoxOfSet<Element, Element>>.Element] {
        super.allValues()
    }
}
