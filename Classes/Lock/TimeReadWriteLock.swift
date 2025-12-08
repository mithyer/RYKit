//
//  TimeReadWriteLock.swift
//  RYKit
//
//  Created by ray on 2025/12/8.
//

import Foundation

public class TimeReadWritLock {
    private var r_semaphore = DispatchSemaphore(value: 1)
    private var w_semaphore = DispatchSemaphore(value: 1)
    private var r_count = 0
    
// MARK: - 读锁
    /// 阻塞式读锁
    public func readLock() {
        r_semaphore.wait()
        r_count += 1
        if r_count == 1 {
            w_semaphore.wait()
        }
        r_semaphore.signal()
    }
    
    /// 带超时的读锁
    @discardableResult
    public func readLock(timeout: DispatchTime) -> Bool {
        r_semaphore.wait()
        r_count += 1
        if r_count == 1 {
            // 第一个读者需要获取写锁
            if w_semaphore.wait(timeout: timeout) != .success {
                // 获取写锁失败，回滚
                r_count -= 1
                r_semaphore.signal()
                return false
            }
        }
        r_semaphore.signal()
        return true
    }
    
    /// 非阻塞式尝试获取读锁
    public func tryReadLock() -> Bool {
        return readLock(timeout: .now())
    }
    
    /// 带超时的读锁（TimeInterval 版本）
    @discardableResult
    public func readLock(timeout: TimeInterval) -> Bool {
        return readLock(timeout: .now() + timeout)
    }
    
    /// 释放读锁
    public func readUnlock() {
        r_semaphore.wait()
        r_count -= 1
        if r_count == 0 {
            w_semaphore.signal()
        }
        r_semaphore.signal()
    }
    
// MARK: - 写锁
    
    /// 阻塞式写锁
    public func writeLock() {
        w_semaphore.wait()
    }
    
    /// 带超时的写锁
    @discardableResult
    public func writeLock(timeout: DispatchTime) -> Bool {
        return w_semaphore.wait(timeout: timeout) == .success
    }
    
    /// 带超时的写锁（TimeInterval 版本）
    @discardableResult
    public func writeLock(timeout: TimeInterval) -> Bool {
        return writeLock(timeout: .now() + timeout)
    }
    
    /// 非阻塞式尝试获取写锁
    public func tryWriteLock() -> Bool {
        return writeLock(timeout: .now())
    }
    
    /// 释放写锁
    public func writeUnlock() {
        w_semaphore.signal()
    }
    
    // MARK: - 便捷方法
    
    /// 执行读操作
    public func read<T>(_ closure: () throws -> T) rethrows -> T {
        readLock()
        defer { readUnlock() }
        return try closure()
    }
    
    /// 执行读操作（带超时）
    public func read<T>(timeout: TimeInterval, _ closure: () throws -> T) rethrows -> T? {
        guard readLock(timeout: timeout) else {
            return nil
        }
        defer { readUnlock() }
        return try closure()
    }
    
    /// 执行写操作
    public func write<T>(_ closure: () throws -> T) rethrows -> T {
        writeLock()
        defer { writeUnlock() }
        return try closure()
    }
    
    /// 执行写操作（带超时）
    public func write<T>(timeout: TimeInterval, _ closure: () throws -> T) rethrows -> T? {
        guard writeLock(timeout: timeout) else {
            return nil
        }
        defer { writeUnlock() }
        return try closure()
    }
}
