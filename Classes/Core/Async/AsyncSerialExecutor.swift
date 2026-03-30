//
//  AsyncSerialExecutor.swift
//  RYKit
//
//  Created by mao rui on 2026/3/27.
//

public actor AsyncSerialExecutor {
    private var running = false
    private var waiters: [CheckedContinuation<Void, Never>] = []
    private var waiterHead = 0

    public init() {}

    private func acquire() async {
        if !running {
            running = true
            return
        }
        await withCheckedContinuation { cont in
            waiters.append(cont)
        }
    }

    private func release() {
        if waiterHead < waiters.count {
            let next = waiters[waiterHead]
            waiterHead += 1
            if waiterHead > 64, waiterHead * 2 >= waiters.count {
                waiters.removeFirst(waiterHead)
                waiterHead = 0
            }
            next.resume()
            return
        }

        running = false
        if !waiters.isEmpty {
            waiters.removeAll(keepingCapacity: true)
        }
        waiterHead = 0
    }

    public func run<T>(
        _ operation: @Sendable () async throws -> T
    ) async throws -> T {
        await acquire()
        defer { release() }
        return try await operation()
    }
}
