//
//  WeakSet.swift
//  RYKit
//
//  Created by mao rui on 2026/1/28.
//

// MARK: - WeakHashTable (弱引用版本)

import Foundation

public class WeakSet<Element: AnyObject & Hashable> {

    // MARK: - WeakBox

    private class WeakBox {
        weak var value: Element?
        let hashValue: Int

        init(value: Element) {
            self.value = value
            self.hashValue = value.hashValue
        }
    }

    // MARK: - Properties

    private var buckets: [[WeakBox]]
    private let loadFactorThreshold: Double = 0.75
    private let minCapacity = 16

    public var count: Int {
        forceCleanup()
        return buckets.reduce(0) { $0 + $1.count }
    }

    public var capacity: Int {
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

    public func insert(_ element: Element) {
        
        let index = bucketIndex(for: element)

        var boxes = buckets[index]
        // 检查是否已存在
        for box in boxes {
            if let existingValue = box.value, existingValue == element {
                return
            }
        }

        boxes.removeAll {
            nil == $0.value
        }
        boxes.append(WeakBox(value: element))
        
        buckets[index] = boxes

        if loadFactor > loadFactorThreshold {
            resize(to: buckets.count * 2)
        }
    }

    @discardableResult
    public func remove(_ element: Element) -> Element? {
        let index = bucketIndex(for: element)
        var removed: Element?
        buckets[index].removeAll { box in
            guard let value = box.value else { return true }
            if value == element {
                removed = value
                return true
            }
            return false
        }
        return removed
    }

    public func contains(_ element: Element) -> Bool {
        let index = bucketIndex(for: element)

        for box in buckets[index] {
            if let value = box.value, value == element {
                return true
            }
        }

        return false
    }

    public func removeAll() {
        buckets = Array(repeating: [], count: minCapacity)
    }

    public func allObjects() -> [Element] {
        
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
    
    /// 强制清理，用于需要准确结果的场景
    private func forceCleanup() {
        for i in 0..<buckets.count {
            buckets[i].removeAll { $0.value == nil }
        }
    }
    
    private func bucketIndex(for element: Element) -> Int {
        return abs(element.hashValue) & (buckets.count - 1)
    }
    
    private var loadFactor: Double {
        let totalCount = buckets.reduce(0) { $0 + $1.count }
        return Double(totalCount) / Double(buckets.count)
    }
    
    private func resize(to newCapacity: Int) {
        let oldBuckets = buckets
        buckets = Array(repeating: [], count: newCapacity)
        
        for bucket in oldBuckets {
            for box in bucket {
                if let value = box.value {
                    let index = bucketIndex(for: value)
                    buckets[index].append(box)
                }
            }
        }
    }
}

// MARK: - Collection for WeakSet

extension WeakSet: Collection {

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
        let snapshot = allObjects()
        return Index(snapshot: snapshot, position: 0)
    }

    public var endIndex: Index {
        let snapshot = allObjects()
        return Index(snapshot: snapshot, position: snapshot.count)
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
