# TinyBufferedKV Debounce Flush Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 将 `TinyBufferedKV` 的定时刷新从常驻 repeating 改为按写入触发的 debounce one-shot，同时保持对外 API 不变。

**Architecture:** 在 `set(data:for:)` 的非阈值分支中调度 one-shot timer；每次新写入都会取消旧 timer 并重建。`flush()` 与 `deinit` 统一走 `cancelFlushTimer()` 清理 timer。timer 触发的 flush 失败仅记录日志，不断言、不自动重试。

**Tech Stack:** Swift 5+, Foundation, DispatchQueue/DispatchSourceTimer, XCTest, async/await

---

## File Structure

- Modify: `Classes/KV/TinyBufferedKV.swift`
  - 责任：debounce timer 生命周期、flush 前后 timer 清理、失败语义。
- Modify: `Project/RYKitTests/TinyBufferedKVTests.swift`
  - 责任：新增 debounce 行为测试（到点触发、后写入重置触发时点）。

---

### Task 1: 新增 Debounce 行为测试（RED）

**Files:**
- Modify: `Project/RYKitTests/TinyBufferedKVTests.swift`
- Test: `Project/RYKitTests/TinyBufferedKVTests.swift`

- [ ] **Step 1: 写第一个失败测试（到点后才落盘）**

```swift
func test_debounceFlush_onlyAfterInterval() async throws {
    let dbName = randomDBName(prefix: "debounce")
    let tableName = "debounce"
    let config = TinyBufferedKV.Config(maxBufferedItems: 100, maxBufferedBytes: 1_048_576, flushInterval: 0.2)
    let kv = TinyBufferedKV(dbName: dbName, tableName: tableName, config: config)
    let rawKV = makeTinyKV(dbName: dbName, tableName: tableName)

    try await kv.set(value: SampleValue(value: "v1"), for: .string("debounce-1"))

    try await assertRawValueMissing(rawKV, key: .string("debounce-1"))

    try await Task.sleep(nanoseconds: 350_000_000)

    let persisted: SampleValue = try await rawKV.getValue(for: .string("debounce-1"))
    XCTAssertEqual(persisted.value, "v1")
}
```

- [ ] **Step 2: 写第二个失败测试（后写入会重置计时）**

```swift
func test_debounceFlush_isResetBySubsequentSet() async throws {
    let dbName = randomDBName(prefix: "debounce-reset")
    let tableName = "debounce-reset"
    let config = TinyBufferedKV.Config(maxBufferedItems: 100, maxBufferedBytes: 1_048_576, flushInterval: 0.2)
    let kv = TinyBufferedKV(dbName: dbName, tableName: tableName, config: config)
    let rawKV = makeTinyKV(dbName: dbName, tableName: tableName)

    try await kv.set(value: SampleValue(value: "first"), for: .string("debounce-reset-1"))
    try await Task.sleep(nanoseconds: 120_000_000)
    try await kv.set(value: SampleValue(value: "second"), for: .string("debounce-reset-2"))

    try await Task.sleep(nanoseconds: 120_000_000)
    try await assertRawValueMissing(rawKV, key: .string("debounce-reset-1"))
    try await assertRawValueMissing(rawKV, key: .string("debounce-reset-2"))

    try await Task.sleep(nanoseconds: 180_000_000)

    let first: SampleValue = try await rawKV.getValue(for: .string("debounce-reset-1"))
    let second: SampleValue = try await rawKV.getValue(for: .string("debounce-reset-2"))
    XCTAssertEqual(first.value, "first")
    XCTAssertEqual(second.value, "second")
}
```

- [ ] **Step 3: 运行新增测试确认 RED**

Run:
```bash
xcodebuild test -project Project/RYKit.xcodeproj -scheme RYKitTests -destination 'platform=iOS Simulator,OS=26.2,name=iPhone 17' -only-testing:RYKitTests/TinyBufferedKVTests/test_debounceFlush_onlyAfterInterval -only-testing:RYKitTests/TinyBufferedKVTests/test_debounceFlush_isResetBySubsequentSet
```

Expected: FAIL（当前实现为 repeating 常驻 timer，不满足“后写入重置计时”）。

- [ ] **Step 4: 提交 RED 测试**

```bash
git add Project/RYKitTests/TinyBufferedKVTests.swift
git commit -m "test: add TinyBufferedKV debounce flush behavior tests"
```

---

### Task 2: 实现 Debounce One-Shot Timer（GREEN）

**Files:**
- Modify: `Classes/KV/TinyBufferedKV.swift`
- Test: `Project/RYKitTests/TinyBufferedKVTests.swift`

- [ ] **Step 1: 删除 init 常驻 timer 启动**

将：
```swift
scheduleFlushTimer()
```

改为：
```swift
// 不在 init 启动常驻 timer，改为写入时按需调度
```

- [ ] **Step 2: 新增统一取消方法**

```swift
private func cancelFlushTimer() {
    timerQueue.sync {
        flushTimer?.setEventHandler {}
        flushTimer?.cancel()
        flushTimer = nil
    }
}
```

- [ ] **Step 3: 新增 debounce 调度方法（one-shot + 重建）**

```swift
private func scheduleDebouncedFlushIfNeeded() {
    guard config.flushInterval > 0 else {
        return
    }

    timerQueue.sync {
        flushTimer?.setEventHandler {}
        flushTimer?.cancel()

        let timer = DispatchSource.makeTimerSource(queue: timerQueue)
        timer.schedule(deadline: .now() + config.flushInterval)
        timer.setEventHandler { [weak self] in
            guard let self else { return }
            Task { [weak self] in
                guard let self else { return }
                do {
                    try await self.flush()
                } catch {
                    print("TinyBufferedKV debounced flush error: \(error)")
                }
            }
        }
        timer.resume()
        flushTimer = timer
    }
}
```

- [ ] **Step 4: 在 set(data:for:) 的非阈值分支调度 debounce**

将：
```swift
if shouldFlush {
    try await flush()
}
```

改为：
```swift
if shouldFlush {
    try await flush()
} else {
    scheduleDebouncedFlushIfNeeded()
}
```

- [ ] **Step 5: 在 flush() 入口先取消 timer**

在 `flush()` 开头添加：
```swift
cancelFlushTimer()
```

确保落盘过程不被旧 timer 重入触发。

- [ ] **Step 6: 在 deinit 使用统一取消方法**

将：
```swift
flushTimer?.setEventHandler {}
flushTimer?.cancel()
```

改为：
```swift
cancelFlushTimer()
```

- [ ] **Step 7: 运行新增 debounce 测试确认 GREEN**

Run:
```bash
xcodebuild test -project Project/RYKit.xcodeproj -scheme RYKitTests -destination 'platform=iOS Simulator,OS=26.2,name=iPhone 17' -only-testing:RYKitTests/TinyBufferedKVTests/test_debounceFlush_onlyAfterInterval -only-testing:RYKitTests/TinyBufferedKVTests/test_debounceFlush_isResetBySubsequentSet
```

Expected: PASS。

- [ ] **Step 8: 提交 GREEN 实现**

```bash
git add Classes/KV/TinyBufferedKV.swift Project/RYKitTests/TinyBufferedKVTests.swift
git commit -m "feat: switch TinyBufferedKV timer to debounced one-shot flush"
```

---

### Task 3: 回归验证与收尾

**Files:**
- Modify: `Classes/KV/TinyBufferedKV.swift`（若回归中发现细节问题）
- Modify: `Project/RYKitTests/TinyBufferedKVTests.swift`（若需稳定时间窗口）
- Test: `Project/RYKitTests/TinyBufferedKVTests.swift`, `Project/RYKitTests/TinyKVTests.swift`

- [ ] **Step 1: 运行 TinyBufferedKV 全量测试**

Run:
```bash
xcodebuild test -project Project/RYKit.xcodeproj -scheme RYKitTests -destination 'platform=iOS Simulator,OS=26.2,name=iPhone 17' -only-testing:RYKitTests/TinyBufferedKVTests
```

Expected: PASS。

- [ ] **Step 2: 运行 TinyKV + TinyBufferedKV 联合回归**

Run:
```bash
xcodebuild test -project Project/RYKit.xcodeproj -scheme RYKitTests -destination 'platform=iOS Simulator,OS=26.2,name=iPhone 17' -only-testing:RYKitTests/TinyKVTests -only-testing:RYKitTests/TinyBufferedKVTests
```

Expected: `** TEST SUCCEEDED **`。

- [ ] **Step 3: 提交回归收尾**

```bash
git add Classes/KV/TinyBufferedKV.swift Project/RYKitTests/TinyBufferedKVTests.swift
git commit -m "test: verify debounced flush behavior and regression coverage"
```

---

## Notes / Guardrails

- 保持 `TinyKV` 不变。
- 不新增对外 API。
- timer 失败路径仅记录，不断言，不自动重试。
- 保持阈值触发立即 flush 行为不变。
- `flush()` 继续对主动调用方抛错，不能吞掉。
