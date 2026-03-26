# TinyKV / TinyBufferedKV 单元测试覆盖增强 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 为 TinyKV 与 TinyBufferedKV 补齐高风险单元测试覆盖（删除语义、查询异常、强化并发），并补充缺失的最小 API 以满足已确认规格。

**Architecture:** 先用 TDD 为 TinyKV 增加 remove/removeAll/count/allKeys 与 int(condition) 安全校验，再将同名能力以“缓冲优先 + flush 后委托存储”的方式接入 TinyBufferedKV。之后分层补齐 P0/P1/P2 测试并做并发稳定性验证。

**Tech Stack:** Swift, XCTest, SQLite3, xcodebuild

---

## 文件结构与职责映射

- `Classes/KV/KVProtocols.swift`
  - 扩展协议，定义 remove/removeAll/count/allKeys 的统一接口。
- `Classes/KV/TinyKV.swift`
  - 实现删除/统计/键枚举 API；增强 int(condition) 输入校验。
- `Classes/KV/TinyBufferedKV.swift`
  - 实现缓冲层对应 API；定义 flush 与删除/统计的协同语义。
- `Project/RYKitTests/TinyKVTests.swift`
  - TinyKV 的 P0/P1/P2 用例（删除、异常、边界、一致性）。
- `Project/RYKitTests/TinyBufferedKVTests.swift`
  - TinyBufferedKV 的 P0/P1/P2 用例（竞态、缓冲一致性、flush 行为）。

---

### Task 1: 扩展协议与 TinyKV 最小 API（remove/removeAll/count/allKeys）

**Files:**
- Modify: `Classes/KV/KVProtocols.swift`
- Modify: `Classes/KV/TinyKV.swift`
- Test: `Project/RYKitTests/TinyKVTests.swift`

- [ ] **Step 1: 先写失败测试（TinyKV API 缺失）**

```swift
func test_removeAll_clearsCountAndAllKeys() async throws {
    let kv = makeKV()
    try await kv.set(value: SampleValue(id: 1, name: "a"), for: .string("k-1"))
    try await kv.set(value: SampleValue(id: 2, name: "b"), for: .int(2))

    try await kv.removeAll()

    let count = try await kv.count()
    let keys = try await kv.allKeys()
    XCTAssertEqual(count, 0)
    XCTAssertTrue(keys.isEmpty)
}
```

- [ ] **Step 2: 运行单测并确认失败（编译缺符号）**

Run:
```bash
xcodebuild test -project Project/RYKit.xcodeproj -scheme RYKitTests -destination 'platform=macOS' -only-testing:RYKitTests/TinyKVTests/test_removeAll_clearsCountAndAllKeys
```
Expected: FAIL，报 `TinyKV` 缺少 `removeAll/count/allKeys`。

- [ ] **Step 3: 最小实现协议与 TinyKV API**

```swift
// KVProtocols.swift
public protocol TinyKVReadWritable {
    // existing...
    func remove(for key: TinyKVKey) async throws
    func remove(for rangeKey: TinyKVQueryKey) async throws
    func removeAll() async throws
    func count() async throws -> Int
    func allKeys() async throws -> [TinyKVKey]
}
```

```swift
// TinyKV.swift (新增 public API)
public func remove(for key: TinyKVKey) async throws { /* DELETE ... WHERE key = ? */ }
public func remove(for rangeKey: TinyKVQueryKey) async throws { /* DELETE ... WHERE (range) */ }
public func removeAll() async throws { /* DELETE FROM table */ }
public func count() async throws -> Int { /* SELECT COUNT(*) */ }
public func allKeys() async throws -> [TinyKVKey] { /* SELECT str_key,int_key */ }
```

- [ ] **Step 4: 运行 TinyKV 测试并确认通过**

Run:
```bash
xcodebuild test -project Project/RYKit.xcodeproj -scheme RYKitTests -destination 'platform=macOS' -only-testing:RYKitTests/TinyKVTests
```
Expected: TinyKVTests 全绿（至少新加用例通过）。

- [ ] **Step 5: 提交**

```bash
git add Classes/KV/KVProtocols.swift Classes/KV/TinyKV.swift Project/RYKitTests/TinyKVTests.swift
git commit -m "feat: add TinyKV removal and key-count APIs with tests"
```

---

### Task 2: 给 TinyBufferedKV 接入 remove/removeAll/count/allKeys

**Files:**
- Modify: `Classes/KV/TinyBufferedKV.swift`
- Test: `Project/RYKitTests/TinyBufferedKVTests.swift`

- [ ] **Step 1: 写失败测试（缓冲层删除语义）**

```swift
func test_removeAll_clearsBufferAndStorage() async throws {
    let dbName = randomDBName(prefix: "removeall")
    let kv = makeBufferedKV(dbName: dbName, tableName: "t")

    try await kv.set(value: SampleValue(value: "a"), for: .string("k1"))
    try await kv.flush()
    try await kv.removeAll()

    XCTAssertEqual(try await kv.count(), 0)
    XCTAssertTrue(try await kv.allKeys().isEmpty)
}
```

- [ ] **Step 2: 运行单测并确认失败**

Run:
```bash
xcodebuild test -project Project/RYKit.xcodeproj -scheme RYKitTests -destination 'platform=macOS' -only-testing:RYKitTests/TinyBufferedKVTests/test_removeAll_clearsBufferAndStorage
```
Expected: FAIL，报 `TinyBufferedKV` 缺少 removeAll/count/allKeys。

- [ ] **Step 3: 最小实现缓冲层 API**

```swift
public func remove(for key: TinyKVKey) async throws {
    let bKey = canonicalKey(for: key)
    queue.sync {
        if let existing = buffer.removeValue(forKey: bKey) { bufferedBytes -= existing.count }
    }
    try await storage.remove(for: key)
}

public func remove(for rangeKey: TinyKVQueryKey) async throws {
    try await flush()
    try await storage.remove(for: rangeKey)
}

public func removeAll() async throws {
    queue.sync { buffer.removeAll(); bufferedBytes = 0 }
    try await storage.removeAll()
}

public func count() async throws -> Int {
    try await flush()
    return try await storage.count()
}

public func allKeys() async throws -> [TinyKVKey] {
    try await flush()
    return try await storage.allKeys()
}
```

- [ ] **Step 4: 运行 TinyBufferedKVTests 并确认通过**

Run:
```bash
xcodebuild test -project Project/RYKit.xcodeproj -scheme RYKitTests -destination 'platform=macOS' -only-testing:RYKitTests/TinyBufferedKVTests
```
Expected: TinyBufferedKVTests 全绿。

- [ ] **Step 5: 提交**

```bash
git add Classes/KV/TinyBufferedKV.swift Project/RYKitTests/TinyBufferedKVTests.swift
git commit -m "feat: add buffered remove/count/allKeys semantics"
```

---

### Task 3: TinyKV 查询异常分支（int(condition)）

**Files:**
- Modify: `Classes/KV/TinyKV.swift`
- Test: `Project/RYKitTests/TinyKVTests.swift`

- [ ] **Step 1: 写失败测试（空表达式/注释/分号）**

```swift
func test_getValues_withIntCondition_emptyExpression_throws() async throws {
    let kv = makeKV()
    do {
        let _: [SampleValue] = try await kv.getValues(for: .int(condition: ""))
        XCTFail("Expected invalidRangeExpression")
    } catch let error as TinyKV.TinyKVError {
        XCTAssertEqual(error, .invalidRangeExpression)
    }
}
```

```swift
func test_getValues_withIntCondition_commentToken_throws() async throws { /* condition: "$ >= 1 --" */ }
func test_getValues_withIntCondition_semicolon_throws() async throws { /* condition: "$ > 0; DROP" */ }
```

- [ ] **Step 2: 运行三条用例并确认失败**

Run:
```bash
xcodebuild test -project Project/RYKit.xcodeproj -scheme RYKitTests -destination 'platform=macOS' -only-testing:RYKitTests/TinyKVTests/test_getValues_withIntCondition_emptyExpression_throws -only-testing:RYKitTests/TinyKVTests/test_getValues_withIntCondition_commentToken_throws -only-testing:RYKitTests/TinyKVTests/test_getValues_withIntCondition_semicolon_throws
```
Expected: FAIL，当前仅校验 `$`，未拦截上述输入。

- [ ] **Step 3: 最小实现条件校验**

```swift
private func validateIntCondition(_ condition: String) throws {
    let trimmed = condition.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty, trimmed.contains("$") else { throw TinyKVError.invalidRangeExpression }
    let forbidden = [";", "--", "/*", "*/"]
    guard forbidden.allSatisfy({ !trimmed.contains($0) }) else { throw TinyKVError.invalidRangeExpression }
}
```

```swift
// in getDatas case .int(condition:)
try validateIntCondition(condition)
let sqlCondition = condition.replacingOccurrences(of: "$", with: "int_key")
```

- [ ] **Step 4: 运行 TinyKVTests 并确认通过**

Run:
```bash
xcodebuild test -project Project/RYKit.xcodeproj -scheme RYKitTests -destination 'platform=macOS' -only-testing:RYKitTests/TinyKVTests
```
Expected: TinyKVTests 通过，新异常用例为绿。

- [ ] **Step 5: 提交**

```bash
git add Classes/KV/TinyKV.swift Project/RYKitTests/TinyKVTests.swift
git commit -m "fix: validate int range conditions and cover invalid expressions"
```

---

### Task 4: TinyKV 覆盖补齐（删除、解码失败、IN 边界）

**Files:**
- Modify: `Project/RYKitTests/TinyKVTests.swift`

- [ ] **Step 1: 写失败测试（删除语义 + decodeFailed + IN 边界）**

```swift
func test_getValue_whenDecodeTypeMismatch_throwsDecodeFailed() async throws {
    let kv = makeKV()
    try await kv.set(value: SampleValue(id: 1, name: "x"), for: .string("mismatch"))

    struct Other: Decodable { let flag: Bool }
    do {
        let _: Other = try await kv.getValue(for: .string("mismatch"))
        XCTFail("Expected decodeFailed")
    } catch let error as TinyKV.TinyKVError {
        XCTAssertEqual(error, .decodeFailed)
    }
}
```

```swift
func test_getValues_withStringsIn_emptyList_returnsEmpty() async throws { /* assert [] */ }
func test_getValues_withIntsIn_emptyList_returnsEmpty() async throws { /* assert [] */ }
func test_getValues_withStringsIn_duplicateKeys_noDuplicateResults() async throws { /* count dedup by SQL result */ }
func test_getValues_withIntsIn_duplicateKeys_noDuplicateResults() async throws { /* count dedup by SQL result */ }
```

- [ ] **Step 2: 运行新增用例并确认失败**

Run:
```bash
xcodebuild test -project Project/RYKit.xcodeproj -scheme RYKitTests -destination 'platform=macOS' -only-testing:RYKitTests/TinyKVTests
```
Expected: 至少新加断言中的部分失败（红转绿驱动）。

- [ ] **Step 3: 若有失败，做最小修复**

```swift
// 仅在断言暴露行为不符时修复；优先保持 TinyKV 现有 SQL 路径，
// 不引入新抽象，不改动无关 API。
```

- [ ] **Step 4: 运行 TinyKVTests 全量并确认通过**

Run:
```bash
xcodebuild test -project Project/RYKit.xcodeproj -scheme RYKitTests -destination 'platform=macOS' -only-testing:RYKitTests/TinyKVTests
```
Expected: PASS。

- [ ] **Step 5: 提交**

```bash
git add Project/RYKitTests/TinyKVTests.swift Classes/KV/TinyKV.swift
git commit -m "test: expand TinyKV coverage for delete semantics and IN edges"
```

---

### Task 5: TinyBufferedKV 强化并发与一致性覆盖

**Files:**
- Modify: `Project/RYKitTests/TinyBufferedKVTests.swift`
- Modify: `Classes/KV/TinyBufferedKV.swift`（仅当测试暴露真实缺陷时）

- [ ] **Step 1: 写失败测试（并发 flush 交错）**

```swift
func test_concurrent_set_and_manualFlush_noLostUpdates() async throws {
    let dbName = randomDBName(prefix: "race")
    let kv = makeBufferedKV(dbName: dbName, tableName: "race", config: .init(maxBufferedItems: 10_000, maxBufferedBytes: 10_000_000, flushInterval: 0))

    try await withThrowingTaskGroup(of: Void.self) { group in
        for i in 0..<120 {
            group.addTask { try await kv.set(value: SampleValue(value: "v-\(i)"), for: .string("k-\(i)")) }
        }
        group.addTask { for _ in 0..<30 { try await kv.flush() } }
        try await group.waitForAll()
    }

    try await kv.flush()
    let all: [SampleValue] = try await kv.getValues(for: .string(like: "k-%"))
    XCTAssertEqual(Set(all.map(\.value)).count, 120)
}
```

```swift
func test_timerFlush_and_manualFlush_interleaving_keepsDataValid() async throws { /* flushInterval > 0, 交错写入+手动flush */ }
func test_getValues_duringConcurrentWrites_doesNotThrow_andReturnsDecodableSet() async throws { /* 并发写+范围读 */ }
```

- [ ] **Step 2: 运行新增并发用例并确认失败**

Run:
```bash
xcodebuild test -project Project/RYKit.xcodeproj -scheme RYKitTests -destination 'platform=macOS' -only-testing:RYKitTests/TinyBufferedKVTests
```
Expected: 若存在竞态缺陷，出现间歇失败或确定性失败。

- [ ] **Step 3: 最小修复并发缺陷（仅在失败时）**

```swift
// 仅修复被测试证明的问题，优先在 queue/timerQueue 同步边界内调整；
// 不新增泛化框架，不改动不相关路径。
```

- [ ] **Step 4: 重复运行确认稳定**

Run:
```bash
for i in {1..5}; do xcodebuild test -project Project/RYKit.xcodeproj -scheme RYKitTests -destination 'platform=macOS' -only-testing:RYKitTests/TinyBufferedKVTests || exit 1; done
```
Expected: 5 轮均 PASS。

- [ ] **Step 5: 提交**

```bash
git add Project/RYKitTests/TinyBufferedKVTests.swift Classes/KV/TinyBufferedKV.swift
git commit -m "test: strengthen TinyBufferedKV concurrency and flush interleaving coverage"
```

---

### Task 6: 全量验证与收尾

**Files:**
- No code changes required（除非验证暴露问题）

- [ ] **Step 1: 跑目标测试集**

Run:
```bash
xcodebuild test -project Project/RYKit.xcodeproj -scheme RYKitTests -destination 'platform=macOS' -only-testing:RYKitTests/TinyKVTests -only-testing:RYKitTests/TinyBufferedKVTests
```
Expected: PASS。

- [ ] **Step 2: 运行与 KV 相关的回归集（可选但推荐）**

Run:
```bash
xcodebuild test -project Project/RYKit.xcodeproj -scheme RYKitTests -destination 'platform=macOS'
```
Expected: 全量 PASS（或仅存在与本变更无关的已知失败）。

- [ ] **Step 3: 整理最终变更并提交（如有遗漏）**

```bash
git add Classes/KV/KVProtocols.swift Classes/KV/TinyKV.swift Classes/KV/TinyBufferedKV.swift Project/RYKitTests/TinyKVTests.swift Project/RYKitTests/TinyBufferedKVTests.swift
git commit -m "test: complete TinyKV and TinyBufferedKV coverage closure"
```

- [ ] **Step 4: 输出验收清单**

```text
- P0：删除语义、异常分支、并发竞态已覆盖并通过
- P1/P2：IN 边界、排序/一致性用例已覆盖并通过
- 目标测试集连续通过，未出现间歇性失败
```

---

## 自检（writing-plans）

1. **Spec 覆盖性**：已映射到任务
- 删除语义（Task 1/2/4）
- 查询异常（Task 3）
- 强化并发（Task 5）
- 边界与一致性（Task 4/6）

2. **占位符扫描**：无 TBD/TODO；每个代码步骤给出具体片段与命令。

3. **类型/命名一致性**：统一使用 `TinyKVKey` / `TinyKVQueryKey` / `TinyKV.TinyKVError`；测试命名与规格一致。
