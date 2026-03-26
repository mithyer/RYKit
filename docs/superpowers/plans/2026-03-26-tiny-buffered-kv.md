# TinyBufferedKV Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Keep `TinyKV` unchanged and add a sibling write-back buffered KV named `TinyBufferedKV` under `Classes/KV`, with in-memory staging + batch persistence.

**Architecture:** `TinyBufferedKV` wraps one internal `TinyKV` instance. `set(...)` writes to an in-memory buffer first, then flushes in batches (time/size thresholds). Single-key `get` checks buffer first; range reads call `flush()` before delegating to `TinyKV` to preserve correctness without implementing a SQL-like in-memory query engine.

**Tech Stack:** Swift 5+, Foundation, SQLite3 (through existing `TinyKV`), XCTest, async/await, DispatchQueue/DispatchSourceTimer.

---

## Design Decision: Relationship with TinyKV

- `TinyBufferedKV` **must use composition** (`private let storage: TinyKV`).
- Do **not** use inheritance (`TinyKV` is `final` and buffering is a strategy wrapper, not subtype behavior).
- Do **not** reimplement SQLite logic from scratch unless plan is explicitly changed; delegate persistence/query to `TinyKV`.
- Keep `TinyKV` behavior and public API unchanged.

---

## File Structure

- Create: `Classes/KV/TinyBufferedKV.swift`
- Create: `Project/RYKitTests/TinyBufferedKVTests.swift`
- Modify: `Classes/KV/TinyBufferedKV.swift` (iterative during tasks)
- Modify: `Project/RYKitTests/TinyBufferedKVTests.swift` (iterative during tasks)

Responsibilities:
- `TinyBufferedKV.swift`: public API, buffering policy, flush lifecycle, delegation to `TinyKV`.
- `TinyBufferedKVTests.swift`: API correctness, buffering semantics, flush policy, concurrency and deinit behavior.

---

### Task 1: Add API Contract Tests (RED)

**Files:**
- Create: `Project/RYKitTests/TinyBufferedKVTests.swift`
- Create (stub only): `Classes/KV/TinyBufferedKV.swift`
- Test: `Project/RYKitTests/TinyBufferedKVTests.swift`

- [ ] **Step 1: Write failing tests for required behavior**

```swift
func test_setThenGet_withoutFlush_readsFromBuffer() async throws
func test_flush_persistsBufferedData_forNewInstance() async throws
func test_bufferLimitReached_triggersAutoFlush() async throws
func test_getValues_flushesBeforeRangeQuery() async throws
```

- [ ] **Step 2: Run tests to verify failure**

Run:
```bash
xcodebuild test -project Project/RYKit.xcodeproj -scheme RYKitTests -destination 'platform=iOS Simulator,OS=26.2,name=iPhone 17' -only-testing:RYKitTests/TinyBufferedKVTests
```

Expected: FAIL (missing `TinyBufferedKV` and/or missing methods).

- [ ] **Step 3: Add minimal class skeleton to compile**

```swift
public final class TinyBufferedKV {
    public init(dbName: String, tableName: String, config: Config = .init()) {}
    public struct Config { ... }
    public func set<T: Encodable>(value: T, for key: TinyKV.Key) async throws { ... }
    public func set(data: Data, for key: TinyKV.Key) async throws { ... }
    public func flush() async throws { ... }
    public func getData(for key: TinyKV.Key) async throws -> Data { ... }
    public func getDatas(for rangeKey: TinyKV.RangeKey, acend: Bool = true) async throws -> [Data] { ... }
    public func getValue<T: Decodable>(for key: TinyKV.Key) async throws -> T { ... }
    public func getValues<T: Decodable>(for rangeKey: TinyKV.RangeKey, acend: Bool = true) async throws -> [T] { ... }
}
```

- [ ] **Step 4: Re-run tests**

Run same command as Step 2.
Expected: FAIL with behavior assertions (not compile errors).

- [ ] **Step 5: Commit**

```bash
git add Project/RYKitTests/TinyBufferedKVTests.swift Classes/KV/TinyBufferedKV.swift
git commit -m "test: add TinyBufferedKV contract tests"
```

---

### Task 2: Implement Single-Key Buffer Read/Write (GREEN)

**Files:**
- Modify: `Classes/KV/TinyBufferedKV.swift`
- Modify: `Project/RYKitTests/TinyBufferedKVTests.swift`
- Test: `Project/RYKitTests/TinyBufferedKVTests.swift`

- [ ] **Step 1: Keep one-key read/write tests failing in isolation**

Run:
```bash
xcodebuild test -project Project/RYKit.xcodeproj -scheme RYKitTests -destination 'platform=iOS Simulator,OS=26.2,name=iPhone 17' -only-testing:RYKitTests/TinyBufferedKVTests/test_setThenGet_withoutFlush_readsFromBuffer
```

Expected: FAIL.

- [ ] **Step 2: Implement minimal buffer model and key canonicalization**

```swift
private enum BufferKey: Hashable {
    case string(String)
    case int(UInt)
}

private var buffer: [BufferKey: Data] = [:]
private let storage: TinyKV
private let queue = DispatchQueue(label: "com.rykit.tinybufferedkv")
```

Implement:
- `set(data:for:)` -> write to `buffer` only.
- `set(value:for:)` -> encode then call `set(data:for:)`.
- `getData(for:)` -> return buffered value if exists, else `try await storage.getData(for:)`.
- `getValue(for:)` -> decode returned data.

- [ ] **Step 3: Run focused tests**

Run:
```bash
xcodebuild test -project Project/RYKit.xcodeproj -scheme RYKitTests -destination 'platform=iOS Simulator,OS=26.2,name=iPhone 17' -only-testing:RYKitTests/TinyBufferedKVTests/test_setThenGet_withoutFlush_readsFromBuffer
```

Expected: PASS.

- [ ] **Step 4: Commit**

```bash
git add Classes/KV/TinyBufferedKV.swift Project/RYKitTests/TinyBufferedKVTests.swift
git commit -m "feat: support buffered single-key reads and writes"
```

---

### Task 3: Implement Batch Flush + Limits

**Files:**
- Modify: `Classes/KV/TinyBufferedKV.swift`
- Modify: `Project/RYKitTests/TinyBufferedKVTests.swift`
- Test: `Project/RYKitTests/TinyBufferedKVTests.swift`

- [ ] **Step 1: Add failing tests for flush behaviors**

Add tests:
- explicit `flush()` persists buffered entries.
- exceeding `maxBufferedItems` triggers auto flush.
- exceeding `maxBufferedBytes` triggers auto flush.

- [ ] **Step 2: Run those tests to confirm RED**

Run:
```bash
xcodebuild test -project Project/RYKit.xcodeproj -scheme RYKitTests -destination 'platform=iOS Simulator,OS=26.2,name=iPhone 17' -only-testing:RYKitTests/TinyBufferedKVTests/test_flush_persistsBufferedData_forNewInstance -only-testing:RYKitTests/TinyBufferedKVTests/test_bufferLimitReached_triggersAutoFlush
```

Expected: FAIL.

- [ ] **Step 3: Implement config and flush pipeline**

```swift
public struct Config {
    public var maxBufferedItems: Int = 200
    public var maxBufferedBytes: Int = 1_048_576
    public var flushInterval: TimeInterval = 0.5
    public init() {}
}
```

Implement:
- tracked counters (`bufferedBytes`).
- `flush()` drains snapshot then batch writes to `storage.set(data:for:)`.
- threshold check in `set(data:for:)`.
- periodic timer-driven flush (`DispatchSourceTimer`) with cancellation in `deinit`.

- [ ] **Step 4: Re-run focused tests**

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Classes/KV/TinyBufferedKV.swift Project/RYKitTests/TinyBufferedKVTests.swift
git commit -m "feat: add TinyBufferedKV flush policy and limits"
```

---

### Task 4: Range Query Consistency and Concurrency

**Files:**
- Modify: `Classes/KV/TinyBufferedKV.swift`
- Modify: `Project/RYKitTests/TinyBufferedKVTests.swift`
- Test: `Project/RYKitTests/TinyBufferedKVTests.swift`

- [ ] **Step 1: Add failing tests for range/query consistency under pending buffer**

Add tests:
- `getDatas/getValues` includes pending writes (by flushing first).
- concurrent `set` + `flush` + `get` has no lost updates in final DB state.

- [ ] **Step 2: Run tests to confirm RED**

Run:
```bash
xcodebuild test -project Project/RYKit.xcodeproj -scheme RYKitTests -destination 'platform=iOS Simulator,OS=26.2,name=iPhone 17' -only-testing:RYKitTests/TinyBufferedKVTests
```

Expected: at least newly added tests fail.

- [ ] **Step 3: Implement range methods and locking order**

Implementation policy:
- `getDatas/getValues` -> `try await flush()` then delegate to `storage`.
- ensure no deadlock between queue-protected buffer and async storage calls.
- ensure flush is idempotent when called concurrently.

- [ ] **Step 4: Re-run test target**

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Classes/KV/TinyBufferedKV.swift Project/RYKitTests/TinyBufferedKVTests.swift
git commit -m "feat: ensure TinyBufferedKV range consistency"
```

---

### Task 5: Final Verification and Documentation

**Files:**
- Modify: `Classes/KV/TinyBufferedKV.swift` (public doc comments)
- Modify: `Project/RYKitTests/TinyBufferedKVTests.swift` (if cleanup needed)

- [ ] **Step 1: Add/verify public API docs**

Ensure doc comments exist for:
- `Config`
- `init`
- `set(value:for:)`
- `set(data:for:)`
- `flush`
- read/query methods

- [ ] **Step 2: Run complete related verification**

Run:
```bash
xcodebuild test -project Project/RYKit.xcodeproj -scheme RYKitTests -destination 'platform=iOS Simulator,OS=26.2,name=iPhone 17' -only-testing:RYKitTests/TinyKVTests -only-testing:RYKitTests/TinyBufferedKVTests
```

Expected: `** TEST SUCCEEDED **`

- [ ] **Step 3: Commit**

```bash
git add Classes/KV/TinyBufferedKV.swift Project/RYKitTests/TinyBufferedKVTests.swift
git commit -m "test: finalize TinyBufferedKV coverage and docs"
```

---

## Notes / Guardrails

- Keep `TinyKV` behavior unchanged.
- New class must be in the same directory: `Classes/KV`.
- Avoid parsing SQL-like range expression in memory; flush-before-range keeps semantics consistent with existing `TinyKV` SQL behavior.
- Memory cap should be byte-based and item-based to avoid uncontrolled growth.
- Flush failures must propagate (`throws`) and never silently drop staged data.
