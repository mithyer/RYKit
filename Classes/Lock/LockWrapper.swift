//
//  LockWrapper.swift
//  RYKit
//
//  Created by mao rui on 2026/1/8.
//

import Foundation
import System

@propertyWrapper
public class LockWrapper<T>: @unchecked Sendable {
    
    private var mutex = os_unfair_lock()
    
    public var _wrappedValue: T
    public var wrappedValue: T {
        set {
            defer {
                os_unfair_lock_unlock(&mutex)
            }
            os_unfair_lock_lock(&mutex)
            _wrappedValue = newValue
        }
        get {
            defer {
                os_unfair_lock_unlock(&mutex)
            }
            os_unfair_lock_lock(&mutex)
            return _wrappedValue
        }
    }

    public init(wrappedValue: T) {
        _wrappedValue = wrappedValue
    }
}

@propertyWrapper
public class RWLockWrapper<T>: @unchecked Sendable {
    
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
