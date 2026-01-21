//
//  ThreadSafeQueue.swift
//  RYKit
//
//  Created by ray on 2026/1/19.
//

import Foundation

public class Queue<T>: LinkedList<T> {
    
    public var front: T? {
        head
    }
    
    public var back: T? {
        tail
    }
    
    public func enqueue(_ item: T) {
        append(item)
    }
    
    public func dequeue() -> T? {
        removeHead()
    }
}


public class ThreadSafeQueue<T>: ThreadSafeLinkedList<T> {
    
    public var front: T? {
        head
    }
    
    public var back: T? {
        tail
    }
    
    public func enqueue(_ item: T) {
        append(item)
    }
    
    public func dequeue() -> T? {
        removeHead()
    }
}
