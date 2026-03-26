//
//  Dispatch+Extension.swift
//  RYKit
//
//  Created by mao rui on 2026/3/26.
//

import Foundation

extension DispatchQueue {

    public func waitTask<T>(sync: Bool = true, _ block: @escaping () throws -> T) async throws -> T {
        try await withCheckedThrowingContinuation { continuation in
            if sync {
                self.async {
                    do {
                        continuation.resume(returning: try block())
                    } catch {
                        continuation.resume(throwing: error)
                    }
                }
            } else {
                do {
                    let res = try self.sync(execute: block)
                    continuation.resume(returning: res)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
}


