//
//  OnceTimeoutTaskQueue.swift
//  RYKit
//
//  Created by mao rui on 2026/1/19.
//

import Foundation

public class OnceTimeoutTaskQueue<T, E: Error>: Queue<OnceTimeoutTask<T, E>> {
    typealias Task =  OnceTimeoutTask<T, E>
    
    private let executeQueue: DispatchQueue
    private var timeoutQueue = DispatchQueue(label: "com.rykit.OnceTimeoutTaskQueue.timeoutQueue", qos: .userInitiated, attributes: .concurrent, autoreleaseFrequency: .workItem)
    private var paused: Bool = false
    private let lock = UnfairLock()
    
    init(executeQueue: DispatchQueue) {
        self.executeQueue = executeQueue
    }
    
    private func check() {
        while let front, front.state.isDone {
            _ = self.dequeue()
        }
        if !paused, let front, !front.state.hasStarted {
            front.perform(by: executeQueue, timeoutQueue: timeoutQueue)
        }
    }
    
    public func addTask(_ task: OnceTimeoutTask<T, E>) {
        lock.lock()
        defer {
            lock.unlock()
        }
        if task.state.hasStarted {
            return
        }
        task.onDone = { [weak self] in
            self?.executeQueue.async {
                self?.check()
            }
        }
        enqueue(task)
        check()
    }
    
    public func pause() {
        lock.lock()
        paused = true
        lock.unlock()
    }
    
    public func resume() {
        lock.lock()
        defer {
            lock.unlock()
        }
        guard paused else {
            return
        }
        paused = false
        check()
    }
}
