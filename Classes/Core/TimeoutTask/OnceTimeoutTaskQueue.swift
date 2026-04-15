//
//  OnceTimeoutTaskQueue.swift
//  RYKit
//
//  Created by mao rui on 2026/1/19.
//

import Combine
import Foundation

/// A priority queue that executes one `OnceTimeoutTask` at a time.
open class OnceTimeoutTaskQueue<T, E: Error> {
    /// Strategy used when a newly added task has higher priority than the current task.
    public enum PreemptionStrategy {
        /// Stop the current task and discard it after stop cleanup.
        case stopCurrentAndDiscard
        /// Let the current task finish before starting the higher-priority task.
        case waitCurrentCompletion
        /// Stop the current task, put it back in the queue, then run by priority.
        case stopCurrentAndRequeue
    }

    /// Event emitted when a task leaves this queue's ownership.
    public struct TaskFinishEvent {
        /// Caller-owned task identifier.
        public let flag: String
        /// The task that finished.
        public let task: OnceTimeoutTask<T, E>
        /// The task's terminal reason at queue removal time.
        public let doneType: OnceTimeoutTask<T, E>.DoneType
    }

    private struct QueuedTask {
        let task: OnceTimeoutTask<T, E>
        let priority: Int
        let sequence: Int
    }

    /// Emits when a task truly leaves queue ownership.
    ///
    /// Requeued tasks do not emit an event for the intermediate stop.
    public let taskDidFinish = PassthroughSubject<TaskFinishEvent, Never>()

    private let executeQueue: DispatchQueue
    private let defaultPreemptionStrategy: PreemptionStrategy
    private let timeoutQueue = DispatchQueue(label: "com.rykit.OnceTimeoutTaskQueue.timeoutQueue", qos: .userInitiated, attributes: .concurrent, autoreleaseFrequency: .workItem)
    private let lock = UnfairLock()
    private var paused: Bool = false
    private var sequence: Int = 0
    private var waiting: [QueuedTask] = []
    private var current: QueuedTask?
    private var stopping: QueuedTask?
    private var stopDisposition: StopDisposition?

    private enum StopDisposition {
        case discard
        case requeue
    }

    /// Creates a serial timeout task queue.
    ///
    /// - Parameters:
    ///   - executeQueue: Queue used to invoke task `execute` closures.
    ///   - defaultPreemptionStrategy: Strategy used when `addTask` does not override it.
    public init(
        executeQueue: DispatchQueue,
        defaultPreemptionStrategy: PreemptionStrategy = .waitCurrentCompletion
    ) {
        self.executeQueue = executeQueue
        self.defaultPreemptionStrategy = defaultPreemptionStrategy
    }

    /// Adds a task with priority.
    ///
    /// Higher numeric priority runs first. Equal priority preserves FIFO order. If the new task's
    /// priority is higher than the current task, the effective preemption strategy is used. If the
    /// current task is non-stoppable, every stop-based strategy behaves as `.waitCurrentCompletion`.
    public func addTask(
        _ task: OnceTimeoutTask<T, E>,
        priority: Int = 0,
        preemptionStrategy: PreemptionStrategy? = nil
    ) {
        guard task.state.canEnqueue else {
            return
        }

        task.onDone = { [weak self, weak task] doneType in
            guard let task else { return }
            self?.handleTaskDone(task, doneType: doneType)
        }

        let item = makeQueuedTask(task: task, priority: priority)
        let strategy = preemptionStrategy ?? defaultPreemptionStrategy
        let taskToStart: QueuedTask?
        let stopRequest: (() -> Void)?

        lock.lock()
        if let current, item.priority > current.priority {
            insert(item)
            let effectiveStrategy = current.task.isStoppable ? strategy : .waitCurrentCompletion
            switch effectiveStrategy {
            case .waitCurrentCompletion:
                stopRequest = nil
            case .stopCurrentAndDiscard:
                stopRequest = prepareStopLocked(disposition: .discard)
            case .stopCurrentAndRequeue:
                stopRequest = prepareStopLocked(disposition: .requeue)
            }
        } else {
            insert(item)
            stopRequest = nil
        }
        taskToStart = takeNextIfPossible()
        lock.unlock()

        stopRequest?()
        start(taskToStart)
    }

    /// Pauses starting additional tasks.
    ///
    /// The current task, if any, continues running.
    public func pause() {
        lock.lock()
        paused = true
        lock.unlock()
    }

    /// Resumes the queue and starts the highest-priority waiting task when possible.
    public func resume() {
        let taskToStart: QueuedTask?

        lock.lock()
        guard paused else {
            lock.unlock()
            return
        }
        paused = false
        taskToStart = takeNextIfPossible()
        lock.unlock()

        start(taskToStart)
    }

    /// Stops all waiting tasks and the current task when they match the filter.
    ///
    /// Waiting tasks and restart-ready tasks stop immediately. If a task is already waiting for
    /// stop cleanup, the queue keeps ownership until `stopped()` or stop timeout, then emits the final event.
    public func stopAll(where block: ((OnceTimeoutTask<T, E>) -> Bool)? = nil) {
        var events: [TaskFinishEvent] = []

        lock.lock()
        let itemsToStop: [QueuedTask]
        if let block {
            itemsToStop = waiting.filter { queued in
                block(queued.task)
            }
            waiting.removeAll { queued in
                block(queued.task)
            }
        } else {
            itemsToStop = waiting
            waiting.removeAll()
        }

        if let stopping, block?(stopping.task) ?? true {
            _ = stopping.task.stopWhileQueued()
            stopDisposition = .discard
        }

        for item in itemsToStop {
            if let doneType = item.task.stopWhileQueued() {
                events.append(TaskFinishEvent(flag: item.task.flag, task: item.task, doneType: doneType))
            }
        }

        let currentStopRequest: (() -> Void)?
        if let current, block?(current.task) ?? true {
            currentStopRequest = prepareStopLocked(disposition: .discard)
        } else {
            currentStopRequest = nil
        }
        let taskToStart = takeNextIfPossible()
        lock.unlock()

        publish(events)
        currentStopRequest?()
        start(taskToStart)
    }

    private func makeQueuedTask(task: OnceTimeoutTask<T, E>, priority: Int) -> QueuedTask {
        lock.lock()
        let item = makeQueuedTaskLocked(task: task, priority: priority)
        lock.unlock()
        return item
    }

    private func makeQueuedTaskLocked(task: OnceTimeoutTask<T, E>, priority: Int) -> QueuedTask {
        sequence += 1
        return QueuedTask(task: task, priority: priority, sequence: sequence)
    }

    private func insert(_ item: QueuedTask) {
        guard let index = waiting.firstIndex(where: { queued in
            item.priority > queued.priority || (item.priority == queued.priority && item.sequence < queued.sequence)
        }) else {
            waiting.append(item)
            return
        }
        waiting.insert(item, at: index)
    }

    private func takeNextIfPossible() -> QueuedTask? {
        guard !paused, current == nil, stopping == nil else {
            return nil
        }
        while let first = waiting.first, first.task.state.isDone {
            waiting.removeFirst()
        }
        guard !waiting.isEmpty else {
            return nil
        }
        let next = waiting.removeFirst()
        current = next
        return next
    }

    private func start(_ item: QueuedTask?) {
        guard let item else {
            return
        }
        item.task.perform(by: executeQueue, timeoutQueue: timeoutQueue)
    }

    private func handleTaskDone(_ task: OnceTimeoutTask<T, E>, doneType: OnceTimeoutTask<T, E>.DoneType) {
        let event: TaskFinishEvent?

        lock.lock()
        if let current, current.task === task {
            self.current = nil
            event = TaskFinishEvent(flag: task.flag, task: task, doneType: doneType)
        } else if let index = waiting.firstIndex(where: { $0.task === task }) {
            waiting.remove(at: index)
            event = TaskFinishEvent(flag: task.flag, task: task, doneType: doneType)
        } else {
            lock.unlock()
            return
        }
        lock.unlock()

        publish([event].compactMap { $0 })

        let taskToStart: QueuedTask?

        lock.lock()
        taskToStart = takeNextIfPossible()
        lock.unlock()

        start(taskToStart)
    }

    /// Prepares a stop request while the queue lock is already held.
    ///
    /// The returned closure must be invoked after releasing the queue lock.
    private func prepareStopLocked(disposition: StopDisposition) -> (() -> Void)? {
        guard stopping == nil, let current else {
            return nil
        }
        let request: (() -> Void)?
        switch disposition {
        case .discard:
            request = current.task.makeStopRequest(timeoutQueue: timeoutQueue, onStopped: { [weak self, weak task = current.task] in
                guard let task else { return }
                self?.handleTaskStopped(task)
            })
        case .requeue:
            request = current.task.makeRestartStopRequest(timeoutQueue: timeoutQueue, onStopped: { [weak self, weak task = current.task] in
                guard let task else { return }
                self?.handleTaskStopped(task)
            })
        }
        guard let request else {
            return nil
        }
        self.current = nil
        stopping = current
        stopDisposition = disposition
        return request
    }

    /// Handles completion of stop cleanup for discard and requeue preemption.
    private func handleTaskStopped(_ task: OnceTimeoutTask<T, E>) {
        let event: TaskFinishEvent?

        lock.lock()
        guard let stopping, stopping.task === task else {
            lock.unlock()
            return
        }

        switch stopDisposition {
        case .requeue:
            if stopping.task.state.canEnqueue {
                insert(makeQueuedTaskLocked(task: stopping.task, priority: stopping.priority))
            }
            event = nil
        case .discard, .none:
            let doneType: OnceTimeoutTask<T, E>.DoneType
            if case .done(let currentDoneType) = task.state {
                doneType = currentDoneType
            } else {
                doneType = .stop
            }
            event = TaskFinishEvent(flag: task.flag, task: task, doneType: doneType)
        }

        self.stopping = nil
        stopDisposition = nil
        lock.unlock()

        publish([event].compactMap { $0 })

        let taskToStart: QueuedTask?

        lock.lock()
        taskToStart = takeNextIfPossible()
        lock.unlock()

        start(taskToStart)
    }

    private func publish(_ events: [TaskFinishEvent]) {
        for event in events {
            taskDidFinish.send(event)
        }
    }
}
