//
//  Combine+More.swift
//  RYKit
//
//  Created by mao rui on 2026/3/13.
//

import Combine
import Foundation

/// A callback wrapper that executes immediately on the first call,
/// then throttles subsequent calls at a specified interval.
///
/// Uses two Combine pipelines internally:
/// - `.first()` ensures the very first `send()` fires the callback synchronously.
/// - `.dropFirst().throttle(latest: true)` coalesces rapid subsequent calls,
///   emitting only the latest within each time window.
///
/// Example:
/// ```swift
/// let throttle = ThrottleCallback(interval: .milliseconds(300)) {
///     print("fired")
/// }
/// throttle.send() // fires immediately
/// throttle.send() // throttled
/// throttle.send() // throttled — latest one fires after 300ms
/// ```
public class ThrottleCallback {

    private let subject: PassthroughSubject<() -> Void, Never>
    private let callback: () -> Void
    private var cancellables = Set<AnyCancellable>()

    /// Creates a new throttled callback.
    /// - Parameters:
    ///   - interval: The minimum time between subsequent callback invocations.
    ///   - scheduler: The scheduler on which throttled callbacks are dispatched. Defaults to `RunLoop.main`.
    ///   - callback: The closure to execute on each non-throttled `send()`.
    public init<S: Scheduler>(interval: S.SchedulerTimeType.Stride, scheduler: S = RunLoop.main, callback: @escaping () -> Void) {

        self.callback = callback
        subject = PassthroughSubject<() -> Void, Never>()

        // Immediate execution for the first call
        subject.first().sink {
            $0()
        }.store(in: &cancellables)

        // Throttle all subsequent calls
        subject.dropFirst().throttle(for: interval, scheduler: scheduler, latest: true).sink {
            $0()
        }.store(in: &cancellables)
    }

    /// Triggers the callback, subject to throttling rules.
    public func send() {
        subject.send(callback)
    }
}
