# OnceTimeoutTask Priority Queue Design

- Date: 2026-04-13
- Repo: `RYKit`
- Authoring mode: Brainstorming -> Design approved by user

## 1. Goal

Extend `OnceTimeoutTask` and `OnceTimeoutTaskQueue` so queued tasks can be prioritized, high-priority insertions can preempt the currently executing task using configurable strategies, and stopped tasks can coordinate actual resource shutdown before the queue starts the next task.

## 2. Scope

In scope:

- Rename task execution timeout API from `timeoutInterval` to `executionTimeoutInterval`.
- Rename `DoneType.timeout` to `DoneType.executionTimeout`.
- Remove the public `done` callback from `OnceTimeoutTask` initialization.
- Add a required `stop` callback to `OnceTimeoutTask` initialization.
- Add a task-level `stopTimeoutInterval` that bounds how long the queue waits for `stopped()`.
- Add async convenience initialization for async `execute` and async `stop`.
- Add task priority and priority-sorted insertion to `OnceTimeoutTaskQueue`.
- Add default queue preemption strategy plus per-`addTask` strategy override.
- Update tests and README examples to match the new public API.

Out of scope:

- Adding new dependencies.
- Adding external task-completion observer APIs.
- Supporting concurrent execution of multiple queued tasks.
- Changing unrelated queue, lock, or collection APIs.
- Guaranteeing cancellation of Swift concurrency `Task` handles created by async convenience initialization.

## 3. Public API Design

### OnceTimeoutTask

`OnceTimeoutTask` remains a one-shot async task from the public caller's perspective.

```swift
public class OnceTimeoutTask<T, E: Error> {
    public enum State {
        case unstart
        case executing
        case done(DoneType)
    }

    public enum DoneType {
        case executionTimeout
        case cancel
        case stop
        case completed(Result<T, E>)
    }

    public typealias Completed = (Result<T, E>) -> Void
    public typealias Stopped = () -> Void
    public typealias Stop = (@escaping Stopped) -> Void

    public init(
        executionTimeoutInterval: DispatchTimeInterval,
        stopTimeoutInterval: DispatchTimeInterval,
        execute: @escaping (@escaping Completed) -> Void,
        stop: @escaping Stop
    )

    public convenience init(
        executionTimeoutInterval: DispatchTimeInterval,
        stopTimeoutInterval: DispatchTimeInterval,
        execute: @escaping () async -> Result<T, E>,
        stop: @escaping () async -> Void
    )

    public func cancel()
    public func stop()
}
```

`stop` is required. Callers with no resource-specific stop work must still pass an explicit implementation, for example `{ stopped in stopped() }`. This keeps the stop contract visible at each call site.

The old initializer with `timeoutInterval` and `done` is not part of the new target API. This is an intentional breaking API cleanup for the feature work. Tests and documentation migrate to the new required stop-aware initializer.

### OnceTimeoutTaskQueue

`OnceTimeoutTaskQueue` executes at most one task at a time and maintains a priority-sorted waiting list.

```swift
public class OnceTimeoutTaskQueue<T, E: Error> {
    public enum PreemptionStrategy {
        case stopCurrentAndDiscard
        case waitCurrentCompletion
        case stopCurrentAndRequeue
    }

    public init(
        executeQueue: DispatchQueue,
        defaultPreemptionStrategy: PreemptionStrategy = .waitCurrentCompletion
    )

    public func addTask(
        _ task: OnceTimeoutTask<T, E>,
        priority: Int = 0,
        preemptionStrategy: PreemptionStrategy? = nil
    )

    public func pause()
    public func resume()
    public func cancelAll()
}
```

`priority` uses `Int`; larger numbers run earlier. Equal priority preserves FIFO order by insertion sequence. Equal priority never preempts the currently executing task.

## 4. Task State Semantics

`perform` starts only when the task is `.unstart`. It moves the task to `.executing`, schedules the execution timeout, and invokes `execute` on the queue's `executeQueue`.

Completion behavior:

- Calling `completed(result)` while executing moves state to `.done(.completed(result))`.
- Reaching `executionTimeoutInterval` while executing moves state to `.done(.executionTimeout)`.
- Calling `cancel()` while executing moves state to `.done(.cancel)`.
- Calling `stop()` while executing immediately moves state to `.done(.stop)`, cancels the execution timeout, and invokes the required `stop(stopped)` closure.
- After any `.done` state, later `completed`, timeout, `cancel`, or `stop` signals are ignored.

The public task init has no `done` callback. External callers inspect `state` when they need to know the final state. Queue progression uses internal closures owned by `RYKit`, not public initialization callbacks.

## 5. Stop Coordination

Stopping has two separate milestones:

1. `task.stop()` marks task state as `.done(.stop)` immediately and calls the task's `stop` closure.
2. The queue waits until either the task's `stopped()` callback fires or `stopTimeoutInterval` expires before starting another task.

This separation prevents stale `completed` or execution timeout callbacks from changing state after stop, while still protecting external resources from overlapping tasks when cleanup is asynchronous.

`stopped()` is single-use for a stop attempt. If both `stopped()` and the stop timeout fire, whichever is observed first advances the queue; the second signal is ignored.

If `stopTimeoutInterval` is `.never`, no fallback timer is scheduled and the queue waits for `stopped()`.

## 6. Queue Ordering And Preemption

The queue stores waiting items with:

- `task`
- `priority`
- monotonic `sequence`

Insertion is sorted by descending `priority`, then ascending `sequence`. This preserves FIFO within the same priority.

The queue also tracks the current executing item and whether it is waiting for a stopped signal. While waiting for stopped, no new task starts.

When adding a task:

- If the task has already started, ignore it.
- If there is no current task and the queue is not paused, start the highest-priority waiting task.
- If there is a current task and new priority is less than or equal to current priority, insert into the waiting list only.
- If there is a current task and new priority is greater than current priority, apply the effective preemption strategy.

The effective preemption strategy is `preemptionStrategy ?? defaultPreemptionStrategy`.

Strategy behavior:

- `.waitCurrentCompletion`: do not stop the current task. Insert the new task by priority and wait for the current task to finish.
- `.stopCurrentAndDiscard`: request stop on the current task. After `stopped()` or stop timeout, discard the stopped task and start the highest-priority waiting task.
- `.stopCurrentAndRequeue`: request stop on the current task. After `stopped()` or stop timeout, reset the stopped task to `.unstart`, reinsert it using its original priority and a new sequence, then start the highest-priority waiting task.

## 7. Internal Implementation Notes

`OnceTimeoutTaskQueue` will not rely on inherited `Queue<OnceTimeoutTask>` storage for priority ordering because the queue must preserve per-item metadata. It will use private storage for waiting items.

`OnceTimeoutTaskQueue` will stop inheriting from `Queue<OnceTimeoutTask>` so inherited `enqueue`, `dequeue`, `front`, or `back` methods cannot bypass priority metadata. The public API for this feature is `addTask`, `pause`, `resume`, and `cancelAll`.

Internal task hooks should be separated by purpose:

- A completion hook for normal completion, execution timeout, and cancel.
- A stopped hook that fires only after `stopped()` or stop timeout.

Queue locks should protect only queue state transitions. User closures (`execute`, `stop`) and dispatch scheduling should not run while holding the queue lock.

The `.stopCurrentAndRequeue` strategy needs an internal-only reset capability. It may reset only a task that was stopped by the queue for requeue. This reset is not public API.

## 8. Async Convenience Initialization

The async initializer bridges to the callback initializer:

- It runs async `execute` in a Swift concurrency task and calls `completed(result)` when the async function returns.
- It runs async `stop` in a Swift concurrency task and calls `stopped()` when the async function returns.
- If async `execute` returns after the task has already stopped, completed is ignored because the state is no longer `.executing`.

The async initializer does not promise to cancel the underlying Swift concurrency task. The caller's `stop` implementation remains responsible for resource-specific cancellation.

## 9. Pause, Resume, And Cancel

`pause()` prevents starting additional tasks. It does not stop or cancel the current task.

`resume()` clears pause and starts the highest-priority waiting task if no current task is executing or waiting for stopped.

`cancelAll()` empties the waiting list and marks each waiting task `.done(.cancel)`. If a task is currently executing, `cancelAll()` marks it `.done(.cancel)`, clears the current execution slot, and does not call `stop`.

If `cancelAll()` is called while the queue is already waiting for `stopped()` from a preemption, the waiting list is emptied and the pending preemption is abandoned. When `stopped()` or stop timeout later fires, the stopped task is discarded and no new task starts.

## 10. Validation Criteria

Tests must cover:

1. New init starts with `.unstart`.
2. Callback `execute` success and failure produce `.done(.completed(result))`.
3. Async `execute` success and failure produce `.done(.completed(result))`.
4. Execution timeout produces `.done(.executionTimeout)`.
5. `stop()` immediately produces `.done(.stop)` and ignores later completion.
6. Queue waits for `stopped()` before starting a preempting task.
7. Queue continues after `stopTimeoutInterval` if `stopped()` is not called.
8. Priority ordering runs larger priority first.
9. Equal priority preserves FIFO and does not preempt current work.
10. `.waitCurrentCompletion` inserts higher-priority work without stopping current work.
11. `.stopCurrentAndDiscard` stops current work, waits for stopped or timeout, then runs the higher-priority task and does not rerun the stopped task.
12. `.stopCurrentAndRequeue` stops current work, waits for stopped or timeout, resets and reinserts the stopped task with its original priority, then runs tasks by priority order.
13. `pause()` and `resume()` preserve priority ordering.
14. `cancelAll()` leaves no queued task able to start afterward.

Verification commands for implementation should include the focused `TimeoutTaskTests` suite and the full Swift test suite when feasible.

## 11. Documentation Updates

README examples should change from:

```swift
OnceTimeoutTask(
    timeoutInterval: .seconds(3),
    execute: { complete in ... },
    done: { result in ... }
)
```

to the new required stop-aware form:

```swift
let task = OnceTimeoutTask<String, Error>(
    executionTimeoutInterval: .seconds(3),
    stopTimeoutInterval: .seconds(1),
    execute: { complete in
        complete(.success("ok"))
    },
    stop: { stopped in
        stopped()
    }
)

let queue = OnceTimeoutTaskQueue<String, Error>(
    executeQueue: .main,
    defaultPreemptionStrategy: .waitCurrentCompletion
)
queue.addTask(task, priority: 10)
```

Docs should state that `stopped()` must be called unless the caller intentionally wants the queue to wait until `stopTimeoutInterval`.
