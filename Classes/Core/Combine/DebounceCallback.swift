import Combine
import Foundation

/// A debounce wrapper that delays callback execution until no new `send()`
/// calls arrive within the specified interval.
///
/// Each `send()` carries its own closure. By default, only the latest closure
/// is emitted after the debounce window ends.
public class DebounceCallback {

    private let subject: PassthroughSubject<() -> Void, Never>
    private var cancellables = Set<AnyCancellable>()

    /// Creates a new debounce wrapper.
    /// - Parameters:
    ///   - interval: The debounce window applied to callback invocations.
    ///   - scheduler: The scheduler on which debounced callbacks are dispatched. Defaults to `RunLoop.main`.
    ///   - shouldPerformFirstImmediately: Whether the first `send()` should execute immediately. Defaults to `false`.
    public init<S: Scheduler>(
        interval: S.SchedulerTimeType.Stride,
        scheduler: S = RunLoop.main,
        shouldPerformFirstImmediately: Bool = false
    ) {
        subject = PassthroughSubject<() -> Void, Never>()

        if shouldPerformFirstImmediately {
            subject.first().sink {
                $0()
            }.store(in: &cancellables)

            subject.dropFirst().debounce(for: interval, scheduler: scheduler).sink {
                $0()
            }.store(in: &cancellables)
        } else {
            subject.debounce(for: interval, scheduler: scheduler).sink {
                $0()
            }.store(in: &cancellables)
        }
    }

    /// Triggers the callback, subject to debounce rules.
    public func send(_ closure: @escaping () -> Void) {
        subject.send(closure)
    }
}
