//
//  LinkedList.swift
//  RYKit
//
//  Created by mao rui on 2026/1/19.
//

class Node<T> {
    var value: T
    var next: Node?
    
    init(value: T, next: Node? = nil) {
        self.value = value
        self.next = next
    }
}

public class LinkedList<T>: CustomStringConvertible {
    
    private var headNode: Node<T>?
    private weak var tailNode: Node<T>?
    public private(set) var count = 0
    
    public var isEmpty: Bool {
        return headNode == nil
    }
    
    public var head: T? {
        headNode?.value
    }
    
    public var tail: T? {
        tailNode?.value
    }
    
    // 在头部插入
    public func prepend(_ value: T) {
        let newNode = Node(value: value, next: headNode)
        headNode = newNode
        if tailNode == nil {
            tailNode = headNode
        }
        count += 1
    }
    
    // 在尾部插入
    public func append(_ value: T) {
        guard !isEmpty else {
            prepend(value)
            return
        }
        let newNode = Node(value: value)
        tailNode?.next = newNode
        tailNode = newNode
        count += 1
    }
    
    // 在指定位置插入
    public func insert(_ value: T, at index: Int) {
        guard index >= 0 && index <= count else {
            // 索引越界
            return
        }
        if index == 0 {
            prepend(value)
            return
        }
        if index == count {
            append(value)
            return
        }
        
        var current = headNode
        for _ in 0..<(index - 1) {
            current = current?.next
        }
        let newNode = Node(value: value, next: current?.next)
        current?.next = newNode
        count += 1
    }
    
    // 删除头部节点
    public func removeHead() -> T? {
        guard let first = headNode else { return nil }
        headNode = headNode?.next
        if isEmpty {
            tailNode = nil
        }
        count -= 1
        return first.value
    }
    
    // 删除所有节点
    public func removeAll() {
        headNode = nil
        tailNode = nil
        count = 0
    }
    
    // 删除指定位置的节点
    public func remove(at index: Int) -> T? {
        guard index >= 0 && index < count else {
            // 索引越界
            return nil
        }
        if index == 0 {
            return removeHead()
        }
        
        var current = headNode
        for _ in 0..<(index - 1) {
            current = current?.next
        }
        let nodeToRemove = current?.next
        current?.next = nodeToRemove?.next
        if index == count - 1 {
            tailNode = current
        }
        count -= 1
        return nodeToRemove?.value
    }
    
    // 获取指定位置的值
    public func value(at index: Int) -> T? {
        guard index >= 0 && index < count else {
            // 索引越界
            return nil
        }
        var current = headNode
        for _ in 0..<index {
            current = current?.next
        }
        return current?.value
    }
    
    // 打印链表
    public var description: String {
        var current = headNode
        var result = "["
        while current != nil {
            result += "\(current!.value)"
            if current?.next != nil {
                result += " -> "
            }
            current = current?.next
        }
        result += "]"
        return result
    }
}

public class ThreadSafeLinkedList<T>: LinkedList<T> {
    
    public let rwLock = ReadWriteLock()
    
    public override var isEmpty: Bool {
        rwLock.read {
            super.isEmpty
        }
    }
    
    public override var head: T? {
        rwLock.read {
            super.head
        }
    }
    
    public override var tail: T? {
        rwLock.read {
            super.tail
        }
    }
    
    public override func prepend(_ value: T) {
        rwLock.write {
            super.prepend(value)
        }
    }
    
    public override func append(_ value: T) {
        rwLock.write {
            super.append(value)
        }
    }
    
    public override func insert(_ value: T, at index: Int) {
        rwLock.write {
            super.insert(value, at: index)
        }
    }
    
    public override func removeHead() -> T? {
        rwLock.write {
            super.removeHead()
        }
    }
    
    public override func removeAll() {
        rwLock.write {
            super.removeAll()
        }
    }
    
    public override func remove(at index: Int) -> T? {
        rwLock.write {
            super.remove(at: index)
        }
    }
    
    public override func value(at index: Int) -> T? {
        rwLock.read {
            super.value(at: index)
        }
    }
}
