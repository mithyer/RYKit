//
//  OnceTimeoutTask.swift
//  RYKit
//
//  Created by mao rui on 2026/1/7.
//

import Foundation
import System


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
        case timeout
        case cancel
        case completed(Result<T, E>)
    }
    
    public typealias Completed = (Result<T, E>) -> Void
    @ThreadSafe public private(set) var state: State = .unstart
    private let timeoutInterval: DispatchTimeInterval
    private var completed: Completed?
    private var timeoutItem: DispatchWorkItem?
    private let execute: (@escaping Completed) -> Void
    var onDone: (() -> Void)?

    public init(timeoutInterval: DispatchTimeInterval,
                execute: @escaping (@escaping Completed) -> Void,
                done: @escaping (DoneType) -> Void) {
        self.execute = execute
        self.timeoutInterval = timeoutInterval
        self.completed = { [weak self] res in
            guard let self, case .executing = state else { return }
            state = .done(.completed(res))
            timeoutItem?.cancel()
            done(.completed(res))
            onDone?()
        }
        timeoutItem = DispatchWorkItem() { [weak self] in
            guard let self, case .executing = state else { return }
            state = .done(.timeout)
            done(.timeout)
            onDone?()
        }
    }
    
    func perform(by executeQueue: DispatchQueue, timeoutQueue: DispatchQueue) {
        guard case .unstart = state, let timeoutItem else {
            return
        }
        state = .executing
        timeoutQueue.asyncAfter(deadline: .now() + timeoutInterval, execute: timeoutItem)
        executeQueue.async { [weak self] in
            guard let self, let completed else { return }
            execute(completed)
        }
    }
    
    public func cancel() {
        guard case .executing = state else { return }
        state = .done(.cancel)
        timeoutItem?.cancel()
    }
}
