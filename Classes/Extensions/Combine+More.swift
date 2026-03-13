//
//  Combine+More.swift
//  RYKit
//
//  Created by mao rui on 2026/3/13.
//

import Combine
import Foundation

/// A throttle wrapper that executes the first `send()` immediately,
/// then throttles subsequent calls at a specified interval.
///
/// Each `send()` carries its own closure. Internally uses two Combine pipelines:
/// - `.first()` ensures the very first `send()` fires its closure synchronously.
/// - `.dropFirst().throttle(latest: true)` coalesces rapid subsequent calls,
///   emitting only the latest closure within each time window.
///
/// Example:
/// ```swift
/// let throttle = ThrottleCallback(interval: .milliseconds(300))
/// throttle.send { print("fired") } // fires immediately
/// throttle.send { print("fired") } // throttled
/// throttle.send { print("fired") } // throttled — latest one fires after 300ms
/// ```
public class ThrottleCallback {

    private let subject: PassthroughSubject<() -> Void, Never>
    private var cancellables = Set<AnyCancellable>()

    /// Creates a new throttle wrapper.
    /// - Parameters:
    ///   - interval: The minimum time between subsequent callback invocations.
    ///   - scheduler: The scheduler on which throttled callbacks are dispatched. Defaults to `RunLoop.main`.
    public init<S: Scheduler>(interval: S.SchedulerTimeType.Stride, scheduler: S = RunLoop.main) {

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
    public func send(_ closure: @escaping () -> Void) {
        subject.send(closure)
    }
}
