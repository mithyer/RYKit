//
//  ReadWriteLock.swift
//  RYKit
//
//  Created by ray on 2025/12/8.
//

import Foundation

public class UnfairLock {
    
    private var mutex = os_unfair_lock_s()
    
    public required init() {}

    public func lock() {
        os_unfair_lock_lock(&mutex)
    }
    
    public func unlock() {
        os_unfair_lock_unlock(&mutex)
    }
    
    public func tryLock() -> Bool {
        os_unfair_lock_trylock(&mutex)
    }
}

