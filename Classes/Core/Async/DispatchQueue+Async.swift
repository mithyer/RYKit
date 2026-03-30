//
//  DispatchQueue+Async.swift
//  RYKit
//
//  Created by mao rui on 2026/3/26.
//

import Foundation

extension DispatchQueue {

    @available(*, deprecated, renamed: "asyncWork")
    public func awaitWork<T>(_ work: @escaping () throws -> T) async throws -> T {
        try await asyncWork(work)
    }

    public func asyncWork<T>(_ work: @escaping () throws -> T) async throws -> T {
        try await withCheckedThrowingContinuation { c in
            self.async {
                do { c.resume(returning: try work()) }
                catch { c.resume(throwing: error) }
            }
        }
    }
}


