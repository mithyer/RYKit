# OnceTimeoutTask Unified Stop Semantics Design

- Date: 2026-04-15
- Repo: `RYKit`
- Authoring mode: Brainstorming -> Design approved by user

## 1. Goal

Unify direct `task.stop()` behavior with queue-driven stop behavior for non-executing stoppable task states.

## 2. Scope

In scope:

- Make `task.stop()` stop queued-but-not-executing tasks immediately.
- Align direct stop semantics with `stopAll(where:)` for `.unstart` and `.waitingRestart(stopped: true)`.
- Preserve cooperative stop closure invocation only for `.executing`.

Out of scope:

- Changing execution timeout behavior.
- Changing queue priority rules.
- Changing `taskDidFinish` payloads.

## 3. Unified Stop Rule

When `task.stop()` is called:

- If `state == .executing`
  - use the normal cooperative stop path
  - call the task's `stopWhenExecuting` closure
  - wait for `stopped()` or stop timeout
- If `state == .unstart`
  - do **not** call the task's `stopWhenExecuting` closure
  - move directly to `.done(.stop)`
- If `state == .waitingRestart(stopped: true)`
  - do **not** call the task's `stopWhenExecuting` closure
  - move directly to `.done(.stop)`
- If `state == .waitingRestart(stopped: false)`
  - keep existing “already stopping” behavior; do not create a second stop flow
- If `state == .done(...)`
  - no-op

This makes direct stop and queue stop semantics consistent for tasks that are queued but not actively executing.

## 4. State Consequences

Direct stop on non-executing startable states becomes:

```text
unstart -> done(.stop)
waitingRestart(stopped: true) -> done(.stop)
```

No `stop` closure is invoked in those transitions.

Direct stop on executing tasks remains:

```text
executing -> done(.stop)
```

with cooperative stop callback execution and stop-wait semantics.

## 5. Testing Requirements

Tests must cover:

1. Direct `task.stop()` on `.unstart` moves state to `.done(.stop)` without calling the stop closure.
2. Direct `task.stop()` on `.waitingRestart(stopped: true)` moves state to `.done(.stop)` without calling the stop closure.
3. Direct `task.stop()` on `.executing` still calls the stop closure and waits for `stopped()` or timeout.
4. Direct `task.stop()` on `.waitingRestart(stopped: false)` does not create duplicate stop behavior.

Verification should include:

```bash
rtk xcodebuild test -project Project/RYKit.xcodeproj -scheme RYKitTests -destination 'platform=macOS' -only-testing:RYKitTests/OnceTimeoutTaskTests BUILD_LIBRARY_FOR_DISTRIBUTION=NO
rtk swift build
```
