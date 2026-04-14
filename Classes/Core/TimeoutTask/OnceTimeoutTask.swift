//
//  OnceTimeoutTask.swift
//  RYKit
//
//  Created by mao rui on 2026/1/7.
//

import Foundation

public class OnceTimeoutTask<T, E: Error> {
    
    public enum State {
        case unstart, executing, waitingRestart(stopped: Bool), done(DoneType)
        
        var isDone: Bool {
            if case .done = self { true } else { false }
        }
        
        var hasStarted: Bool {
            if case .unstart = self { false } else { true }
        }

        var canStart: Bool {
            switch self {
            case .unstart, .waitingRestart(stopped: true):
                return true
            case .executing, .waitingRestart(stopped: false), .done:
                return false
            }
        }

        var canEnqueue: Bool {
            canStart
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
    let executionTimeoutInterval: DispatchTimeInterval?
    let stopTimeoutInterval: DispatchTimeInterval?
    
    private let execute: (@escaping Completed) -> Void
    private let stopAction: Stop?
    private let lock = UnfairLock()
    private var currentState: State = .unstart
    private var runGeneration: UInt64 = 0
    private var stopGeneration: UInt64 = 0
    private var executionTimeoutItem: DispatchWorkItem?
    private var stopTimeoutItem: DispatchWorkItem?
    private var stopFinished: (() -> Void)?
    
    var onDone: ((DoneType) -> Void)?

    var isStoppable: Bool {
        stopAction != nil
    }
    
    public var state: State {
        lock.lock()
        defer { lock.unlock() }
        return currentState
    }
    
    public init(
        flag: String,
        executionTimeoutInterval: DispatchTimeInterval?,
        stopTimeoutInterval: DispatchTimeInterval?,
        execute: @escaping (@escaping Completed) -> Void,
        stop: Stop?
    ) {
        self.flag = flag
        self.executionTimeoutInterval = executionTimeoutInterval
        self.stopTimeoutInterval = stopTimeoutInterval
        self.execute = execute
        self.stopAction = stop
    }
    
    public convenience init(
        flag: String,
        executionTimeoutInterval: DispatchTimeInterval?,
        stopTimeoutInterval: DispatchTimeInterval?,
        execute: @escaping () async -> Result<T, E>,
        stop: (() async -> Void)?
    ) {
        let bridgedStop: Stop? = stop.map { stop in
            { stopped in
                Task {
                    await stop()
                    stopped()
                }
            }
        }
        self.init(
            flag: flag,
            executionTimeoutInterval: executionTimeoutInterval,
            stopTimeoutInterval: stopTimeoutInterval,
            execute: { completed in
                Task {
                    completed(await execute())
                }
            },
            stop: bridgedStop
        )
    }
    
    func perform(by executeQueue: DispatchQueue, timeoutQueue: DispatchQueue) {
        lock.lock()
        guard currentState.canStart else {
            lock.unlock()
            return
        }
        runGeneration &+= 1
        let generation = runGeneration
        let timeoutItem: DispatchWorkItem?
        if executionTimeoutInterval != nil {
            timeoutItem = DispatchWorkItem { [weak self] in
                self?.finish(with: .executionTimeout, notify: true, runGeneration: generation)
            }
        } else {
            timeoutItem = nil
        }
        let completed: Completed = { [weak self] result in
            self?.finish(with: .completed(result), notify: true, runGeneration: generation)
        }
        currentState = .executing
        executionTimeoutItem = timeoutItem
        let interval = executionTimeoutInterval
        let execute = self.execute
        lock.unlock()
        
        if let timeoutItem, let interval {
            timeoutQueue.asyncAfter(deadline: .now() + interval, execute: timeoutItem)
        }
        executeQueue.async {
            execute(completed)
        }
    }
    
    public func cancel() {
        finish(with: .cancel, notify: true, runGeneration: nil)
    }
    
    public func stop() {
        guard let request = makeStopRequest(timeoutQueue: .global(qos: .userInitiated), onStopped: { [weak self] in
            self?.notifyDone(.stop)
        }) else {
            return
        }
        request()
    }
    
    @discardableResult
    func cancelFromQueue() -> DoneType? {
        transitionToCancel(allowUnstarted: true, notify: false)
    }
    
    func makeStopRequest(timeoutQueue: DispatchQueue, onStopped: @escaping () -> Void) -> (() -> Void)? {
        makeStopRequest(
            timeoutQueue: timeoutQueue,
            stoppedState: .done(.stop),
            onStopped: onStopped
        )
    }

    func makeRestartStopRequest(timeoutQueue: DispatchQueue, onStopped: @escaping () -> Void) -> (() -> Void)? {
        makeStopRequest(
            timeoutQueue: timeoutQueue,
            stoppedState: .waitingRestart(stopped: true),
            onStopped: onStopped
        )
    }

    private func makeStopRequest(
        timeoutQueue: DispatchQueue,
        stoppedState: State,
        onStopped: @escaping () -> Void
    ) -> (() -> Void)? {
        lock.lock()
        guard case .executing = currentState else {
            lock.unlock()
            return nil
        }
        guard let stopAction else {
            lock.unlock()
            return nil
        }
        stopGeneration &+= 1
        let generation = stopGeneration
        let stopTimeoutItem = DispatchWorkItem { [weak self] in
            self?.finishStop(stoppedState: stoppedState, stopGeneration: generation)
        }
        let stopped: Stopped = { [weak self] in
            self?.finishStop(stoppedState: stoppedState, stopGeneration: generation)
        }
        switch stoppedState {
        case .waitingRestart:
            currentState = .waitingRestart(stopped: false)
        default:
            currentState = .done(.stop)
        }
        executionTimeoutItem?.cancel()
        executionTimeoutItem = nil
        self.stopTimeoutItem = stopTimeoutItem
        stopFinished = onStopped
        let interval = stopTimeoutInterval
        lock.unlock()
        
        if let interval, case .never = interval {
        } else if let interval {
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
        runGeneration &+= 1
        stopGeneration &+= 1
        currentState = .unstart
        return true
    }

    func setWaitingRestart(stopped: Bool) {
        lock.lock()
        currentState = .waitingRestart(stopped: stopped)
        lock.unlock()
    }

    @discardableResult
    func markWaitingRestartStopped() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard case .waitingRestart(stopped: false) = currentState else {
            return false
        }
        currentState = .waitingRestart(stopped: true)
        return true
    }
    
    private func finish(with doneType: DoneType, notify: Bool, runGeneration expectedRunGeneration: UInt64?) {
        let doneHandler: ((DoneType) -> Void)?
        
        lock.lock()
        guard case .executing = currentState else {
            lock.unlock()
            return
        }
        if let expectedRunGeneration, expectedRunGeneration != runGeneration {
            lock.unlock()
            return
        }
        currentState = .done(doneType)
        executionTimeoutItem?.cancel()
        executionTimeoutItem = nil
        doneHandler = notify ? onDone : nil
        lock.unlock()
        
        doneHandler?(doneType)
    }
    
    private func transitionToCancel(allowUnstarted: Bool, notify: Bool) -> DoneType? {
        let doneHandler: ((DoneType) -> Void)?
        
        lock.lock()
        switch currentState {
        case .executing:
            break
        case .unstart where allowUnstarted:
            break
        case .waitingRestart where allowUnstarted:
            break
        default:
            lock.unlock()
            return nil
        }
        currentState = .done(.cancel)
        runGeneration &+= 1
        executionTimeoutItem?.cancel()
        executionTimeoutItem = nil
        doneHandler = notify ? onDone : nil
        lock.unlock()
        
        doneHandler?(.cancel)
        return .cancel
    }

    private func notifyDone(_ doneType: DoneType) {
        let doneHandler: ((DoneType) -> Void)?

        lock.lock()
        doneHandler = onDone
        lock.unlock()

        doneHandler?(doneType)
    }
    
    private func finishStop(stoppedState: State, stopGeneration expectedStopGeneration: UInt64) {
        let handler: (() -> Void)?
        
        lock.lock()
        guard let stopFinished, expectedStopGeneration == stopGeneration else {
            lock.unlock()
            return
        }
        if case .waitingRestart(stopped: false) = currentState {
            currentState = stoppedState
        }
        handler = stopFinished
        self.stopFinished = nil
        stopTimeoutItem?.cancel()
        stopTimeoutItem = nil
        lock.unlock()
        
        handler?()
    }
}
