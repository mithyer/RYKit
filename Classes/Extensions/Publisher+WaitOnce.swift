//
//  Publisher+WaitOnce.swift
//  RYKit
//
//  Created by mao rui on 2026/1/9.
//

import Combine
import Foundation

public struct TimeoutError: Error {}

extension Result where Failure == TimeoutError {
    
    public var isTimeout: Bool {
        if case .failure = self {
            return true
        }
        return false
    }
    
    public var output: Success? {
        if case .success(let output) = self {
            return output
        }
        return nil
    }
}

extension Publisher where Failure == Never {
    
    public func waitOnce<T: Scheduler>(until: @escaping (Output) -> Bool = {_ in true},
                                       scheduler: T = DispatchQueue.main,
                                       options: T.SchedulerOptions? = nil,
                                       timeout: T.SchedulerTimeType.Stride,
                                       result: @escaping (Result<Output, TimeoutError>) -> Void) -> AnyCancellable {
        let valuePublisher = self
            .setFailureType(to: TimeoutError.self)
            .first(where: until)
            .map { Result<Output, TimeoutError>.success($0) }
        
        let timeoutPublisher = Just(Result<Output, TimeoutError>.failure(TimeoutError()))
            .delay(for: timeout, scheduler: scheduler)
            .setFailureType(to: TimeoutError.self)
        
        return Publishers.Merge(valuePublisher, timeoutPublisher)
            .first()
            .receive(on: scheduler)
            .sink(
                receiveCompletion: { _ in },
                receiveValue: { res in
                    result(res)
                }
            )
    }
    
    public func waitOnce<T: Scheduler>(until: @escaping (Output) -> Bool = {_ in true},
                                       scheduler: T = DispatchQueue.main,
                                       options: T.SchedulerOptions? = nil,
                                       timeout: T.SchedulerTimeType.Stride,
                                       setCancelation with: inout AnyCancellable?) async -> Result<Output, TimeoutError> {
        await withCheckedContinuation { continuation in
            with = waitOnce(until: until, scheduler: scheduler, options: options, timeout: timeout) { res in
                continuation.resume(returning: res)
            }
        }
    }
    
    public func waitOnce<T: Scheduler>(until: @escaping (Output) -> Bool = {_ in true},
                                       scheduler: T = DispatchQueue.main,
                                       options: T.SchedulerOptions? = nil,
                                       timeout: T.SchedulerTimeType.Stride,
                                       setCancelation to: Associatable,
                                       cancelationOptions: (key: String, doNotStoreIfHasSameKey: Bool)? = nil) async -> Result<Output, TimeoutError> {
        await withCheckedContinuation { continuation in
            waitOnce(until: until, scheduler: scheduler, options: options, timeout: timeout) { res in
                continuation.resume(returning: res)
            }.ry.store(to: to, with: cancelationOptions?.key, doNotStoreIfHasSameKey: cancelationOptions?.doNotStoreIfHasSameKey ?? false)
        }
    }
}

extension Publisher where Output: Equatable, Failure == Never {
    
    public func waitOnce<T: Scheduler>(for output: Output,
                                       scheduler: T = DispatchQueue.main,
                                       options: T.SchedulerOptions? = nil,
                                       timeout: T.SchedulerTimeType.Stride,
                                       result: @escaping (Result<Output, TimeoutError>) -> Void) -> AnyCancellable {
        waitOnce(until: { $0 == output }, scheduler: scheduler, options: options, timeout: timeout, result: result)
    }
    
    public func waitOnce<T: Scheduler>(for output: Output,
                                       scheduler: T = DispatchQueue.main,
                                       options: T.SchedulerOptions? = nil,
                                       timeout: T.SchedulerTimeType.Stride,
                                       setCancelation with: inout AnyCancellable?) async -> Result<Output, TimeoutError> {
        await waitOnce(until: { $0 == output }, scheduler: scheduler, options: options, timeout: timeout, setCancelation: &with)
    }
    
    public func waitOnce<T: Scheduler>(for output: Output,
                                       scheduler: T = DispatchQueue.main,
                                       options: T.SchedulerOptions? = nil,
                                       timeout: T.SchedulerTimeType.Stride,
                                       setCancelation to: Associatable,
                                       cancelationOptions: (key: String, doNotStoreIfHasSameKey: Bool)? = nil) async -> Result<Output, TimeoutError> {
        await waitOnce(until: { $0 == output }, scheduler: scheduler, options: options, timeout: timeout, setCancelation: to, cancelationOptions: cancelationOptions)
    }
}

extension DispatchTimeInterval {
    
    public var stride: DispatchQueue.SchedulerTimeType.Stride {
        switch self {
        case .seconds(let int):
            .seconds(int)
        case .milliseconds(let int):
            .milliseconds(int)
        case .microseconds(let int):
            .microseconds(int)
        case .nanoseconds(let int):
            .nanoseconds(int)
        case .never:
            .seconds(.infinity)
        @unknown default:
            .zero
        }
    }
}
