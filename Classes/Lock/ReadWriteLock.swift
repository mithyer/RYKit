//
//  ReadWriteLock.swift
//  RYKit
//
//  Created by ray on 2025/12/8.
//

import Foundation

public class ReadWriteLock {
    private var rwlock = pthread_rwlock_t()
    
    public init() {
        pthread_rwlock_init(&rwlock, nil)
    }
    
    deinit {
        pthread_rwlock_destroy(&rwlock)
    }
    
    // 读锁
    public func readLock() {
        pthread_rwlock_rdlock(&rwlock)
    }
    
    // 写锁
    public func writeLock() {
        pthread_rwlock_wrlock(&rwlock)
    }
    
    // 尝试读锁（非阻塞）
    public func tryReadLock() -> Bool {
        return pthread_rwlock_tryrdlock(&rwlock) == 0
    }
    
    // 尝试写锁（非阻塞）
    public func tryWriteLock() -> Bool {
        return pthread_rwlock_trywrlock(&rwlock) == 0
    }
    
    // 解锁
    public func unlock() {
        pthread_rwlock_unlock(&rwlock)
    }
    
    // 读操作
    public func read<T>(_ closure: () throws -> T) rethrows -> T {
        pthread_rwlock_rdlock(&rwlock)
        defer { pthread_rwlock_unlock(&rwlock) }
        return try closure()
    }
    
    // 写操作
    public func write<T>(_ closure: () throws -> T) rethrows -> T {
        pthread_rwlock_wrlock(&rwlock)
        defer { pthread_rwlock_unlock(&rwlock) }
        return try closure()
    }
}

