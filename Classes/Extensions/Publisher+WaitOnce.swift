//
//  Publisher+WaitOnce.swift
//  RYKit
//
//  Created by mao rui on 2026/1/9.
//

import Combine
import Foundation

public struct TimeoutError: Error {}

extension Publisher where Output: Equatable, Failure == Never {
    
    public func waitOnce<T: Scheduler>(_ output: Output,
                                       scheduler: T = DispatchQueue.main,
                                       options: T.SchedulerOptions? = nil,
                                       timeoutSeconds: TimeInterval,
                                       result: @escaping (Result<Output, TimeoutError>) -> Void) -> AnyCancellable {
        setFailureType(to: TimeoutError.self).first(where: {
            $0 == output
        }).timeout(.seconds(timeoutSeconds), scheduler: scheduler, options: options)
            .receive(on: scheduler)
            .sink { res in
            switch res {
            case .finished:
                break
            case .failure(let err):
                result(.failure(err))
            }
        } receiveValue: { output in
            result(.success(output))
        }
    }
    
    public func waitOnce<T: Scheduler>(_ output: Output,
                                       scheduler: T = DispatchQueue.main,
                                       options: T.SchedulerOptions? = nil,
                                       timeoutSeconds: TimeInterval,
                                       setCancelation with: inout AnyCancellable?) async -> Result<Output, TimeoutError> {
        await withCheckedContinuation { continuation in
            with = waitOnce(output, scheduler: scheduler, options: options, timeoutSeconds: timeoutSeconds) { res in
                continuation.resume(returning: res)
            }
        }
    }
    
    public func waitOnce<T: Scheduler>(_ output: Output,
                                       scheduler: T = DispatchQueue.main,
                                       options: T.SchedulerOptions? = nil,
                                       timeoutSeconds: TimeInterval,
                                       setCancelation to: Associatable,
                                       cancelationOptions: (key: String, doNotStoreIfHasSameKey: Bool)? = nil) async -> Result<Output, TimeoutError> {
        await withCheckedContinuation { continuation in
            waitOnce(output, scheduler: scheduler, options: options, timeoutSeconds: timeoutSeconds) { res in
                continuation.resume(returning: res)
            }.ry.store(to: to, with: cancelationOptions?.key, doNotStoreIfHasSameKey: cancelationOptions?.doNotStoreIfHasSameKey ?? false)
        }
    }
}
