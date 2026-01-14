//
//  LockWrapper.swift
//  RYKit
//
//  Created by mao rui on 2026/1/8.
//

import Foundation
import System

public protocol AnyLock: AnyObject {
    init()
    func lock()
    func unlock()
}

extension NSLock: AnyLock {}
extension UnfairLock: AnyLock {}

public class _ThreadSafe<T, L: AnyLock>: @unchecked Sendable {
    
    public class Wrapper<K: _ThreadSafe<T, L>> {

        let ts: K
        init(ts: K) {
            self.ts = ts
        }
        
        @discardableResult
        public func lock<R>(_ closure: (inout T) throws -> R) rethrows -> R {
            try ts.lock(closure)
        }
    }
    
    fileprivate var _lock: L
    private var _wrappedValue: T
    
    public var wrappedValue: T {
        set {
            defer {
                _lock.unlock()
            }
            _lock.lock()
            _wrappedValue = newValue
        }
        get {
            defer {
                _lock.unlock()
            }
            _lock.lock()
            return _wrappedValue
        }
    }
    
    public init(wrappedValue: T) {
        _wrappedValue = wrappedValue
        _lock = L()
    }
    
    fileprivate func lock<R>(_ closure: (inout T) throws -> R) rethrows -> R {
        defer {
            _lock.unlock()
        }
        _lock.lock()
        return try closure(&_wrappedValue)
    }
}

@propertyWrapper
public class ThreadSafe<T>: _ThreadSafe<T, UnfairLock>, @unchecked Sendable {
    
    public override var wrappedValue: T {
        set {
            super.wrappedValue = newValue
        }
        get {
            super.wrappedValue
        }
    }
    
    public var projectedValue: Wrapper<ThreadSafe<T>> {
        Wrapper(ts: self)
    }
}


@propertyWrapper
public class RWThreadSafe<T> {
    
    public class Wrapper<K: RWThreadSafe<T>> {
        let ts: K
        init(ts: K) {
            self.ts = ts
        }
        
        @discardableResult
        func read<R>(_ closure: (inout T) throws -> R) rethrows -> R {
            try ts.read(closure)
        }
        
        @discardableResult
        func write<R>(_ closure: (inout T) throws -> R) rethrows -> R {
            try ts.write(closure)
        }
    }
    
    private var _lock = ReadWriteLock()
    
    public var _wrappedValue: T
    public var wrappedValue: T {
        set {
            defer {
                _lock.unlock()
            }
            _lock.writeLock()
            _wrappedValue = newValue
        }
        get {
            defer {
                _lock.unlock()
            }
            _lock.readLock()
            return _wrappedValue
        }
    }

    public init(wrappedValue: T) {
        _wrappedValue = wrappedValue
    }
    
    fileprivate func read<R>(_ closure: (inout T) throws -> R) rethrows -> R {
        try _lock.read {
            try closure(&_wrappedValue)
        }
    }
    
    fileprivate func write<R>(_ closure: (inout T) throws -> R) rethrows -> R {
        try _lock.write {
            try closure(&_wrappedValue)
        }
    }
    
    public var projectedValue: Wrapper<RWThreadSafe<T>> {
        return Wrapper(ts: self)
    }
}
