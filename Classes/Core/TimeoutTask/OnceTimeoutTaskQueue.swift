//
//  OnceTimeoutTaskQueue.swift
//  RYKit
//
//  Created by mao rui on 2026/1/19.
//

import Combine
import Foundation

public class OnceTimeoutTaskQueue<T, E: Error> {
    public enum PreemptionStrategy {
        case stopCurrentAndDiscard
        case waitCurrentCompletion
        case stopCurrentAndRequeue
    }

    public struct TaskFinishEvent {
        public let flag: String
        public let task: OnceTimeoutTask<T, E>
        public let doneType: OnceTimeoutTask<T, E>.DoneType
    }

    private struct QueuedTask {
        let task: OnceTimeoutTask<T, E>
        let priority: Int
        let sequence: Int
    }

    public let taskDidFinish = PassthroughSubject<TaskFinishEvent, Never>()

    private let executeQueue: DispatchQueue
    private let defaultPreemptionStrategy: PreemptionStrategy
    private let timeoutQueue = DispatchQueue(label: "com.rykit.OnceTimeoutTaskQueue.timeoutQueue", qos: .userInitiated, attributes: .concurrent, autoreleaseFrequency: .workItem)
    private let lock = UnfairLock()
    private var paused: Bool = false
    private var sequence: Int = 0
    private var waiting: [QueuedTask] = []
    private var current: QueuedTask?

    public init(
        executeQueue: DispatchQueue,
        defaultPreemptionStrategy: PreemptionStrategy = .waitCurrentCompletion
    ) {
        self.executeQueue = executeQueue
        self.defaultPreemptionStrategy = defaultPreemptionStrategy
    }

    public func addTask(
        _ task: OnceTimeoutTask<T, E>,
        priority: Int = 0,
        preemptionStrategy: PreemptionStrategy? = nil
    ) {
        guard !task.state.hasStarted else {
            return
        }

        task.onDone = { [weak self, weak task] doneType in
            guard let task else { return }
            self?.handleTaskDone(task, doneType: doneType)
        }

        let item = makeQueuedTask(task: task, priority: priority)
        let taskToStart: QueuedTask?

        lock.lock()
        insert(item)
        taskToStart = takeNextIfPossible()
        lock.unlock()

        start(taskToStart)
    }

    public func pause() {
        lock.lock()
        paused = true
        lock.unlock()
    }

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

    public func cancelAll() {
        var events: [TaskFinishEvent] = []

        lock.lock()
        let itemsToCancel = waiting
        waiting.removeAll()
        for item in itemsToCancel {
            if let doneType = item.task.cancelFromQueue() {
                events.append(TaskFinishEvent(flag: item.task.flag, task: item.task, doneType: doneType))
            }
        }
        if let current, let doneType = current.task.cancelFromQueue() {
            self.current = nil
            events.append(TaskFinishEvent(flag: current.task.flag, task: current.task, doneType: doneType))
        }
        lock.unlock()

        publish(events)
    }

    private func makeQueuedTask(task: OnceTimeoutTask<T, E>, priority: Int) -> QueuedTask {
        lock.lock()
        sequence += 1
        let nextSequence = sequence
        lock.unlock()
        return QueuedTask(task: task, priority: priority, sequence: nextSequence)
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
        guard !paused, current == nil, !waiting.isEmpty else {
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
        guard let current, current.task === task else {
            lock.unlock()
            return
        }
        self.current = nil
        event = TaskFinishEvent(flag: task.flag, task: task, doneType: doneType)
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
