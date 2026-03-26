# TinyBufferedKV Contract Tests Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Document the TinyBufferedKV API contract via focused XCTest cases so the intended buffering and flush semantics are captured before a full implementation.

**Architecture:** TinyBufferedKV will wrap TinyKV and maintain an in-memory buffer that flushes to TinyKV either explicitly, when the buffer limit is hit, or before range queries. The tests will use temporary SQLite files so that two instances sharing the same db file can verify persistence and auto-flush requirements.

**Tech Stack:** Swift 5/XCTest, TinyKV (SQLite), `xcodebuild`.

---
I'm using the writing-plans skill to create the implementation plan.

### Task 1: Capture contract in tests

**Files:**
- Create: `Project/RYKitTests/TinyBufferedKVTests.swift`

- [ ] **Step 1: Write the failing test file**
```swift
@MainActor
final class TinyBufferedKVTests: XCTestCase {
    func makeBufferedKV() throws -> TinyBufferedKV {
        let dbURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        return TinyBufferedKV(dbName: dbURL.lastPathComponent, tableName: "buffered", config: .init(bufferLimit: 2))
    }

    func test_setThenGet_withoutFlush_readsFromBuffer() async throws {
        let kv = try makeBufferedKV()
        let expected = "value".data(using: .utf8)!
        try await kv.set(data: expected, for: .string("hello"))
        XCTAssertEqual(try await kv.getData(for: .string("hello")), expected)
    }

    func test_flush_persistsBufferedData_forNewInstance() async throws {
        let dbName = UUID().uuidString
        do {
            let kv = TinyBufferedKV(dbName: dbName, tableName: "buffered", config: .init())
            try await kv.set(value: "v1", for: .string("shared"))
            try await kv.flush()
        }
        let reader = TinyBufferedKV(dbName: dbName, tableName: "buffered", config: .init())
        let value: String = try await reader.getValue(for: .string("shared"))
        XCTAssertEqual(value, "v1")
    }

    func test_bufferLimitReached_triggersAutoFlush() async throws {
        let kv = try makeBufferedKV()
        try await kv.set(value: "one", for: .string("k1"))
        try await kv.set(value: "two", for: .string("k2"))
        let stored: [String] = try await kv.getValues(for: .string(like: "k%"))
        XCTAssertEqual(stored, ["one", "two"])
    }

    func test_getValues_flushesBeforeRangeQuery() async throws {
        let kv = try makeBufferedKV()
        try await kv.set(value: "pending", for: .string("range-1"))
        try await kv.getValues(for: .string(like: "range-%"))
        // verify callback or helper that range query triggered flush (can check TinyKV directly once available)
    }
}
```
(Add assertions that call TinyBufferedKV API and expect buffered data to be visible immediately, reused after flush, auto-flushed on limit breach, and flushed before range queries.)

- [ ] **Step 2: Run tests to confirm failure**
Run: `xcodebuild test -project Project/RYKit.xcodeproj -scheme RYKitTests -destination 'platform=iOS Simulator,OS=26.2,name=iPhone 17' -only-testing:RYKitTests/TinyBufferedKVTests`
Expected: FAIL because `TinyBufferedKV` or its required methods are missing.

### Task 2: Add stub implementation

**Files:**
- Create: `Classes/KV/TinyBufferedKV.swift`

- [ ] **Step 1: Implement stub contract**
```swift
import Foundation

public final class TinyBufferedKV {
    public struct Config {
        public let bufferLimit: Int
        public init(bufferLimit: Int = 2) {
            self.bufferLimit = bufferLimit
        }
    }

    private let tinyKV: TinyKV
    private var buffer = [TinyKV.Key: Data]()

    public init(dbName: String, tableName: String, config: Config) {
        self.tinyKV = TinyKV(dbName: dbName, tableName: tableName)
    }

    public func set<T: Encodable>(value: T, for key: TinyKV.Key) async throws {
        try await set(data: JSONEncoder().encode(value), for: key)
    }

    public func set(data: Data, for key: TinyKV.Key) async throws {
        fatalError("not implemented")
    }

    public func flush() async throws {
        fatalError("not implemented")
    }

    public func getData(for key: TinyKV.Key) async throws -> Data {
        fatalError("not implemented")
    }

    public func getDatas(for rangeKey: TinyKV.RangeKey, acend: Bool = true) async throws -> [Data] {
        fatalError("not implemented")
    }

    public func getValue<T: Decodable>(for key: TinyKV.Key) async throws -> T {
        fatalError("not implemented")
    }

    public func getValues<T: Decodable>(for rangeKey: TinyKV.RangeKey, acend: Bool = true) async throws -> [T] {
        fatalError("not implemented")
    }
}
```
(The fatalError stubs keep the build green until behavior-driven assertions run.)

- [ ] **Step 2: Re-run tests**
Run same `xcodebuild` command as before. Expected: still FAIL because tests assert behavior that the stub does not fulfill.

### Task 3: Commit contract work

**Files:**
- Create: `Project/RYKitTests/TinyBufferedKVTests.swift`
- Create: `Classes/KV/TinyBufferedKV.swift`

- [ ] **Step 1: Stage and commit**
```
git add Project/RYKitTests/TinyBufferedKVTests.swift Classes/KV/TinyBufferedKV.swift
git commit -m "test: add TinyBufferedKV contract tests"
```
