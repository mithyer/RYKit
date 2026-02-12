//
//  WeakMap.swift
//  RYKit
//
//  Created by mao rui on 2026/2/11.
//

// 基于hash表的基本原理实现swift版本的WeakMap和Set，对应NSHashMap和NSHashTable

import Foundation

public protocol WeakBoxProtocol {
    
    associatedtype Key: Hashable & Equatable
    associatedtype Element: AnyObject
    var value: Element? { get }
    var key: Key? { get }
    var hashValue: Int { get }
    init(key: Key, value: Element)
}

public class WeakBoxOfMap<Key: Hashable & Equatable, Element: AnyObject>: WeakBoxProtocol {
    
    public weak var value: Element?
    public let key: Key?
    public let hashValue: Int
    public required init(key: Key, value: Element) {
        self.value = value
        self.key = key
        self.hashValue = key.hashValue
    }
}

public class WeakMap<Key: Hashable & Equatable, Element: AnyObject>: _WeakMap<WeakBoxOfMap<Key, Element>> {}

/// 注意：非线程安全。多线程场景请在外部加锁或包装为线程安全版本。
public class _WeakMap<WeakBox: WeakBoxProtocol> {
    // MARK: - Properties
    
    public typealias Key = WeakBox.Key
    public typealias Element = WeakBox.Element

    private var buckets: [[WeakBox]]
    private let loadFactorThreshold: Double = 0.75
    private let minCapacity = 16

    public var count: Int {
        let count = forceCleanup()
        return count
    }

    private var capacity: Int {
        return buckets.count
    }

    public var isEmpty: Bool {
        count == 0
    }

    // MARK: - Initialization

    public init(capacity: Int = 16) {
        let actualCapacity = Swift.max(capacity, minCapacity).nextPowerOfTwo()
        self.buckets = Array(repeating: [], count: actualCapacity)
    }

    // MARK: - Operations

    public func insert(key: Key, _ element: Element) {
        
        let index = bucketIndex(for: key)

        var boxes = buckets[index]
        // 检查是否已存在
        for box in boxes {
            if box.key == key, box.value != nil {
                return
            }
        }

        boxes.removeAll {
            nil == $0.value
        }
        boxes.append(WeakBox(key: key, value: element))
        
        buckets[index] = boxes

        if loadFactor > loadFactorThreshold {
            resize(to: buckets.count * 2)
        }
    }

    @discardableResult
    public func remove(_ key: Key) -> Element? {
        let index = bucketIndex(for: key)
        var removed: Element?
        buckets[index].removeAll { box in
            guard let value = box.value else { return true }
            if box.key == key {
                removed = value
                return true
            }
            return false
        }
        shrinkIfNeeded()
        return removed
    }

    public subscript(key: Key) -> Element? {
        get {
            let index = bucketIndex(for: key)
            for box in buckets[index] {
                if box.key == key {
                    return box.value
                }
            }
            return nil
        }
        set {
            if let value = newValue {
                insert(key: key, value)
            } else {
                remove(key)
            }
        }
    }

    public func contains(_ key: Key) -> Bool {
        let index = bucketIndex(for: key)

        for box in buckets[index] {
            if box.key == key, box.value != nil {
                return true
            }
        }

        return false
    }

    public func removeAll() {
        buckets = Array(repeating: [], count: minCapacity)
    }

    public func allValues() -> [Element] {
        
        var result: [Element] = []

        for i in 0..<buckets.count {
            buckets[i].removeAll { box in
                if let value = box.value {
                    result.append(value)
                    return false
                }
                return true
            }
        }
        
        return result
    }
    
    public func allKeys() -> [Key] {
        
        var result: [Key] = []

        for i in 0..<buckets.count {
            buckets[i].removeAll { box in
                if let key = box.key, box.value != nil {
                    result.append(key)
                    return false
                }
                return true
            }
        }
        
        return result
    }
    
    /// 强制清理，用于需要准确结果的场景
    private func forceCleanup() -> Int {
        var existCount = 0
        for i in 0..<buckets.count {
            buckets[i].removeAll {
                if $0.value == nil {
                    return true
                }
                existCount += 1
                return false
            }
        }
        return existCount
    }
    
    private func bucketIndex(for key: Key) -> Int {
        // buckets.count 始终是 2 的幂，掩码自动清除符号位，无需 abs()
        return key.hashValue & (buckets.count - 1)
    }
    
    private var loadFactor: Double {
        let aliveCount = buckets.reduce(0) { count, bucket in
            count + bucket.count { $0.value != nil }
        }
        return Double(aliveCount) / Double(buckets.count)
    }
    
    private func shrinkIfNeeded() {
        let newCapacity = buckets.count / 2
        guard newCapacity >= minCapacity, loadFactor < 0.1 else { return }
        resize(to: newCapacity)
    }

    private func resize(to newCapacity: Int) {
        let oldBuckets = buckets
        buckets = Array(repeating: [], count: newCapacity)
        
        for bucket in oldBuckets {
            for box in bucket {
                if let key = box.key {
                    let index = bucketIndex(for: key)
                    buckets[index].append(box)
                }
            }
        }
    }
}

// MARK: - Collection for WeakSet

extension _WeakMap: Collection {

    /// A snapshot-based index for WeakSet.
    /// Since WeakSet elements can be deallocated at any time,
    /// the index captures a snapshot at creation time.
    public struct Index: Comparable {
        fileprivate let snapshot: [Element]
        fileprivate let position: Int

        public static func < (lhs: Index, rhs: Index) -> Bool {
            lhs.position < rhs.position
        }

        public static func == (lhs: Index, rhs: Index) -> Bool {
            lhs.position == rhs.position
        }

        fileprivate var endIndex: Index {
            Index(snapshot: snapshot, position: snapshot.count)
        }
    }

    public var startIndex: Index {
        let snapshot = allValues()
        return Index(snapshot: snapshot, position: 0)
    }

    public var endIndex: Index {
        // for-in 先调 startIndex 再调 endIndex。
        // startIndex 的 allValues() 已清理了死引用，
        // 此处只需数存活数量（不再分配 snapshot），保证 position 一致。
        // subscript 和 index(after:) 都基于 startIndex 的 snapshot 驱动。
        let aliveCount = buckets.reduce(0) { $0 + $1.count }
        return Index(snapshot: [], position: aliveCount)
    }

    public subscript(position: Index) -> Element {
        position.snapshot[position.position]
    }

    public func index(after i: Index) -> Index {
        Index(snapshot: i.snapshot, position: i.position + 1)
    }

    /// Returns indices that share the same snapshot for consistent iteration.
    /// Use this instead of `startIndex..<endIndex` for index-based iteration.
    public func indices(snapshot: Bool = true) -> Range<Index> {
        let start = startIndex
        return start..<start.endIndex
    }
}

// MARK: - Helper Extensions

fileprivate extension Int {
    /// 返回大于等于当前值的最小 2 的幂
    func nextPowerOfTwo() -> Int {
        guard self > 0 else { return 1 }
        var n = self - 1
        n |= n >> 1
        n |= n >> 2
        n |= n >> 4
        n |= n >> 8
        n |= n >> 16
        return n + 1
    }
}
