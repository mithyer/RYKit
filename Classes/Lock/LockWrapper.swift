//
//  LockWrapper.swift
//  RYKit
//
//  Created by mao rui on 2026/1/8.
//

import Foundation
import System

public protocol AnyMutex {
    mutating func install()
    mutating func lock()
    mutating func unlock()
    mutating func dispose()
}

extension AnyMutex {
    public func install() {}
    public func dispose() {}
}

extension NSLock: AnyMutex {}

extension os_unfair_lock: AnyMutex {
    public mutating func lock() { os_unfair_lock_lock(&self) }
    public mutating func unlock() { os_unfair_lock_unlock(&self) }
}
extension pthread_mutex_t: AnyMutex {
    public mutating func install() { pthread_mutex_init(&self, nil) }
    public mutating func lock() { pthread_mutex_lock(&self) }
    public mutating func unlock() { pthread_mutex_unlock(&self) }
    public mutating func dispose() { pthread_mutex_destroy(&self) }
}

public class LockReferWrapper<T, L: AnyMutex>: @unchecked Sendable {
    
    private var mutex: L
    private var _wrappedValue: T
    
    public var wrappedValue: T {
        set {
            defer {
                mutex.unlock()
            }
            mutex.lock()
            _wrappedValue = newValue
        }
        get {
            defer {
                mutex.unlock()
            }
            mutex.lock()
            return _wrappedValue
        }
    }

    public init(wrappedValue: T, mutex: L) {
        _wrappedValue = wrappedValue
        self.mutex = mutex
        self.mutex.install()
    }
    
    deinit {
        mutex.dispose()
    }
}

@propertyWrapper
public class LockWrapper<T>: LockReferWrapper<T, os_unfair_lock>, @unchecked Sendable {
    
    public override var wrappedValue: T {
        set {
            super.wrappedValue = newValue
        }
        get {
            super.wrappedValue
        }
    }
    
    public init(wrappedValue: T) {
        super.init(wrappedValue: wrappedValue, mutex: os_unfair_lock_s())
    }
}

@propertyWrapper
public class RWLockWrapper<T> {
    
    private var mutex = pthread_rwlock_t()
    
    public var _wrappedValue: T
    public var wrappedValue: T {
        set {
            defer {
                pthread_rwlock_unlock(&mutex)
            }
            pthread_rwlock_wrlock(&mutex)
            _wrappedValue = newValue
        }
        get {
            defer {
                pthread_rwlock_unlock(&mutex)
            }
            pthread_rwlock_rdlock(&mutex)
            return _wrappedValue
        }
    }

    public init(wrappedValue: T) {
        pthread_rwlock_init(&mutex, nil)
        _wrappedValue = wrappedValue
    }
    
    deinit {
        pthread_rwlock_destroy(&mutex)
    }
}
