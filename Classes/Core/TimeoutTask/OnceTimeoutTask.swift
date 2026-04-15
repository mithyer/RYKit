//
//  OnceTimeoutTask.swift
//  RYKit
//
//  Created by mao rui on 2026/1/7.
//

import Foundation

/// A single-use asynchronous task with optional execution timeout and cooperative stop support.
open class OnceTimeoutTask<T, E: Error> {
    
    /// The lifecycle state of a task.
    public enum State {
        /// The task has never started.
        case unstart
        /// The task is currently executing.
        case executing
        /// The task was stopped by a queue for restart and is waiting to run again.
        ///
        /// `stopped == false` means the queue is still waiting for `stopped()` or stop timeout.
        /// `stopped == true` means stop cleanup finished and the task can be started again.
        case waitingRestart(stopped: Bool)
        /// The task has reached a terminal state.
        case done(DoneType)
        
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
    
    /// The terminal reason for a task.
    public enum DoneType {
        /// The task did not complete before `executionTimeoutInterval`.
        case executionTimeout
        /// The task was stopped and will not be restarted by the queue.
        case stop
        /// The task completed with its result.
        case completed(Result<T, E>)
    }
    
    /// Completion callback passed to `execute`.
    public typealias Completed = (Result<T, E>) -> Void
    /// Callback that a stop closure must call after stop cleanup completes.
    public typealias Stopped = () -> Void
    /// Cooperative stop closure. Call `Stopped` when resources are actually stopped.
    public typealias Stop = (@escaping Stopped) -> Void
    
    /// Caller-owned identifier for queue finish events and diagnostics.
    public let flag: String
    let executionTimeoutInterval: DispatchTimeInterval?
    let stopTimeoutInterval: DispatchTimeInterval?
    
    private let execute: (@escaping Completed) -> Void
    private let stopAction: Stop
    private let lock = UnfairLock()
    private var currentState: State = .unstart
    private var runGeneration: UInt64 = 0
    private var stopGeneration: UInt64 = 0
    private var executionTimeoutItem: DispatchWorkItem?
    private var stopTimeoutItem: DispatchWorkItem?
    private var stopFinished: (() -> Void)?
    
    var onDone: ((DoneType) -> Void)?

    /// Whether this task supports cooperative stop.
    var isStoppable: Bool {
        true
    }
    
    /// The current task state.
    public var state: State {
        lock.lock()
        defer { lock.unlock() }
        return currentState
    }
    
    /// Creates a callback-based timeout task.
    ///
    /// - Parameters:
    ///   - flag: Caller-owned identifier used by queue finish events.
    ///   - executionTimeoutInterval: Maximum execution duration. Pass `nil` to disable execution timeout.
    ///   - stopTimeoutInterval: Maximum time to wait for `stopped()`. Pass `nil` to wait indefinitely.
    ///   - execute: Starts the task and receives a one-shot completion callback.
    ///   - stop: Cooperative stop closure.
    public init(
        flag: String,
        executionTimeoutInterval: DispatchTimeInterval?,
        stopTimeoutInterval: DispatchTimeInterval?,
        execute: @escaping (@escaping Completed) -> Void,
        stop: @escaping Stop = { stopped in stopped() }
    ) {
        self.flag = flag
        self.executionTimeoutInterval = executionTimeoutInterval
        self.stopTimeoutInterval = stopTimeoutInterval
        self.execute = execute
        self.stopAction = stop
    }
    
    /// Creates an async timeout task.
    ///
    /// The async `execute` result is bridged to the callback-based initializer. The queue waits
    /// until the async stop closure returns.
    public convenience init(
        flag: String,
        executionTimeoutInterval: DispatchTimeInterval?,
        stopTimeoutInterval: DispatchTimeInterval?,
        execute: @escaping () async -> Result<T, E>,
        stop: @escaping () async -> Void = {}
    ) {
        let bridgedStop: Stop = { stopped in
            Task {
                await stop()
                stopped()
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
    
    /// Starts the task on the provided queue if the current state can run.
    ///
    /// This is internal queue infrastructure. It accepts `.unstart` and
    /// `.waitingRestart(stopped: true)` states only.
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
    
    /// Requests cooperative stop for an executing task.
    ///
    /// The task enters `.done(.stop)` immediately and notifies listeners after `stopped()` or stop timeout.
    public func stop() {
        guard let request = makeStopRequest(timeoutQueue: .global(qos: .userInitiated), onStopped: { [weak self] in
            self?.notifyDone(.stop)
        }) else {
            return
        }
        request()
    }
    
    /// Builds a final-stop request for queue-owned stop/discard flows.
    func makeStopRequest(timeoutQueue: DispatchQueue, onStopped: @escaping () -> Void) -> (() -> Void)? {
        makeStopRequest(
            timeoutQueue: timeoutQueue,
            stoppedState: .done(.stop),
            onStopped: onStopped
        )
    }

    /// Builds a restart-stop request for queue requeue flows.
    ///
    /// The task enters `.waitingRestart(stopped: false)` immediately and moves to
    /// `.waitingRestart(stopped: true)` after `stopped()` or stop timeout.
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
        executionTimeoutItem = nil
        self.stopTimeoutItem = stopTimeoutItem
        stopFinished = onStopped
        let interval = stopTimeoutInterval
        lock.unlock()
        
        if let interval, case .never = interval {
        } else if let interval {
            timeoutQueue.asyncAfter(deadline: .now() + interval, execute: stopTimeoutItem)
        }
        
        return { [self] in
            stopAction(stopped)
        }
    }

    @discardableResult
    func stopWhileQueued() -> DoneType? {
        lock.lock()
        switch currentState {
        case .unstart, .waitingRestart(stopped: true):
            currentState = .done(.stop)
            runGeneration &+= 1
            stopGeneration &+= 1
            executionTimeoutItem = nil
            stopTimeoutItem = nil
            stopFinished = nil
            lock.unlock()
            return .stop
        default:
            lock.unlock()
            return nil
        }
    }

    /// Legacy internal reset hook retained for existing tests; queue requeue no longer uses it.
    @discardableResult
    func resetForRequeue() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard case .done(.stop) = currentState else {
            return false
        }
        stopTimeoutItem = nil
        stopFinished = nil
        executionTimeoutItem = nil
        runGeneration &+= 1
        stopGeneration &+= 1
        currentState = .unstart
        return true
    }

    /// Internal state hook used by tests and restart orchestration.
    func setWaitingRestart(stopped: Bool) {
        lock.lock()
        currentState = .waitingRestart(stopped: stopped)
        lock.unlock()
    }

    /// Marks a restart-waiting task as ready to be started again.
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
        executionTimeoutItem = nil
        doneHandler = notify ? onDone : nil
        lock.unlock()
        
        doneHandler?(doneType)
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
        stopTimeoutItem = nil
        lock.unlock()
        
        handler?()
    }
}
