//
//  OnceTimeoutTask.swift
//  RYKit
//
//  Created by mao rui on 2026/1/7.
//

import Foundation

public class OnceTimeoutTask<T, E: Error> {
    
    public enum State {
        case unstart, executing, done(DoneType)
        
        var isDone: Bool {
            if case .done = self { true } else { false }
        }
        
        var hasStarted: Bool {
            if case .unstart = self { false } else { true }
        }
    }
    
    public enum DoneType {
        case executionTimeout
        case cancel
        case stop
        case completed(Result<T, E>)
    }
    
    public typealias Completed = (Result<T, E>) -> Void
    public typealias Stopped = () -> Void
    public typealias Stop = (@escaping Stopped) -> Void
    
    public let flag: String
    let executionTimeoutInterval: DispatchTimeInterval
    let stopTimeoutInterval: DispatchTimeInterval
    
    private let execute: (@escaping Completed) -> Void
    private let stopAction: Stop
    private let lock = UnfairLock()
    private var currentState: State = .unstart
    private var executionTimeoutItem: DispatchWorkItem?
    private var stopTimeoutItem: DispatchWorkItem?
    private var stopFinished: (() -> Void)?
    
    var onDone: (() -> Void)?
    
    public var state: State {
        lock.lock()
        defer { lock.unlock() }
        return currentState
    }
    
    public init(
        flag: String,
        executionTimeoutInterval: DispatchTimeInterval,
        stopTimeoutInterval: DispatchTimeInterval,
        execute: @escaping (@escaping Completed) -> Void,
        stop: @escaping Stop
    ) {
        self.flag = flag
        self.executionTimeoutInterval = executionTimeoutInterval
        self.stopTimeoutInterval = stopTimeoutInterval
        self.execute = execute
        self.stopAction = stop
    }
    
    public convenience init(
        flag: String,
        executionTimeoutInterval: DispatchTimeInterval,
        stopTimeoutInterval: DispatchTimeInterval,
        execute: @escaping () async -> Result<T, E>,
        stop: @escaping () async -> Void
    ) {
        self.init(
            flag: flag,
            executionTimeoutInterval: executionTimeoutInterval,
            stopTimeoutInterval: stopTimeoutInterval,
            execute: { completed in
                Task {
                    completed(await execute())
                }
            },
            stop: { stopped in
                Task {
                    await stop()
                    stopped()
                }
            }
        )
    }
    
    func perform(by executeQueue: DispatchQueue, timeoutQueue: DispatchQueue) {
        let timeoutItem = DispatchWorkItem { [weak self] in
            self?.finish(with: .executionTimeout, notify: true)
        }
        let completed: Completed = { [weak self] result in
            self?.finish(with: .completed(result), notify: true)
        }
        
        lock.lock()
        guard case .unstart = currentState else {
            lock.unlock()
            return
        }
        currentState = .executing
        executionTimeoutItem = timeoutItem
        let interval = executionTimeoutInterval
        let execute = self.execute
        lock.unlock()
        
        timeoutQueue.asyncAfter(deadline: .now() + interval, execute: timeoutItem)
        executeQueue.async {
            execute(completed)
        }
    }
    
    public func cancel() {
        finish(with: .cancel, notify: true)
    }
    
    public func stop() {
        guard let request = makeStopRequest(timeoutQueue: .global(qos: .userInitiated), onStopped: {}) else {
            return
        }
        request()
    }
    
    @discardableResult
    func cancelFromQueue() -> DoneType? {
        transitionToCancel(allowUnstarted: true, notify: false)
    }
    
    func makeStopRequest(timeoutQueue: DispatchQueue, onStopped: @escaping () -> Void) -> (() -> Void)? {
        let stopTimeoutItem = DispatchWorkItem { [weak self] in
            self?.finishStop()
        }
        let stopped: Stopped = { [weak self] in
            self?.finishStop()
        }
        
        lock.lock()
        guard case .executing = currentState else {
            lock.unlock()
            return nil
        }
        currentState = .done(.stop)
        executionTimeoutItem?.cancel()
        executionTimeoutItem = nil
        self.stopTimeoutItem = stopTimeoutItem
        stopFinished = onStopped
        let interval = stopTimeoutInterval
        let stopAction = self.stopAction
        lock.unlock()
        
        if case .never = interval {
        } else {
            timeoutQueue.asyncAfter(deadline: .now() + interval, execute: stopTimeoutItem)
        }
        
        return {
            stopAction(stopped)
        }
    }
    
    @discardableResult
    func resetForRequeue() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard case .done(.stop) = currentState else {
            return false
        }
        stopTimeoutItem?.cancel()
        stopTimeoutItem = nil
        stopFinished = nil
        executionTimeoutItem = nil
        currentState = .unstart
        return true
    }
    
    private func finish(with doneType: DoneType, notify: Bool) {
        let doneHandler: (() -> Void)?
        
        lock.lock()
        guard case .executing = currentState else {
            lock.unlock()
            return
        }
        currentState = .done(doneType)
        executionTimeoutItem?.cancel()
        executionTimeoutItem = nil
        doneHandler = notify ? onDone : nil
        lock.unlock()
        
        doneHandler?()
    }
    
    private func transitionToCancel(allowUnstarted: Bool, notify: Bool) -> DoneType? {
        let doneHandler: (() -> Void)?
        
        lock.lock()
        switch currentState {
        case .executing:
            break
        case .unstart where allowUnstarted:
            break
        default:
            lock.unlock()
            return nil
        }
        currentState = .done(.cancel)
        executionTimeoutItem?.cancel()
        executionTimeoutItem = nil
        doneHandler = notify ? onDone : nil
        lock.unlock()
        
        doneHandler?()
        return .cancel
    }
    
    private func finishStop() {
        let handler: (() -> Void)?
        
        lock.lock()
        guard let stopFinished else {
            lock.unlock()
            return
        }
        handler = stopFinished
        self.stopFinished = nil
        stopTimeoutItem?.cancel()
        stopTimeoutItem = nil
        lock.unlock()
        
        handler?()
    }
}
