# DebounceCallback Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 为 RYKitCore 新增一个与 ThrottleCallback 风格一致的 DebounceCallback，并通过 TDD 验证默认防抖与“首次立即执行”两种语义。

**Architecture:** 实现保持与现有 ThrottleCallback 一致的轻量封装风格，核心仍是 `PassthroughSubject<() -> Void, Never>` 加 `AnyCancellable`。默认模式使用单条 `debounce` 管道；开启 `shouldPerformFirstImmediately` 时使用 `first()` 与 `dropFirst().debounce(...)` 两条管道拆分首次与后续事件，避免单次回调被执行两次。

**Tech Stack:** Swift 5+, Combine, XCTest, Foundation

---

## File Structure

- Create: `Classes/Core/Combine/DebounceCallback.swift`
  - 新增公开类型 `DebounceCallback`，对外暴露 `init(interval:scheduler:shouldPerformFirstImmediately:)` 与 `send(_:)`。
- Create: `Project/RYKitTests/DebounceCallbackTests.swift`
  - 新增 XCTest 用例，覆盖默认 debounce、首次立即执行、自定义 scheduler 与生命周期行为。
- Reference: `Classes/Core/Combine/ThrottleCallback.swift`
  - 参考既有 API 风格、注释风格与 Combine 管道拆分方式。
- Reference: `Project/RYKitTests/ThrottleCallbackTests.swift`
  - 参考现有测试命名、异步等待方式与断言粒度。

### Task 1: 搭建默认 debounce 语义

**Files:**
- Create: `Project/RYKitTests/DebounceCallbackTests.swift`
- Create: `Classes/Core/Combine/DebounceCallback.swift`
- Reference: `Project/RYKitTests/ThrottleCallbackTests.swift`

- [ ] **Step 1: 写第一个 failing test，验证默认模式单次发送不会立即执行，只会在静默窗口结束后执行**

```swift
import XCTest
import Combine
@testable import RYKit

final class DebounceCallbackTests: XCTestCase {

    func test_singleSend_executesOnlyAfterDebounceInterval() {
        var callCount = 0
        let callback = DebounceCallback(interval: .milliseconds(100))

        callback.send { callCount += 1 }

        XCTAssertEqual(callCount, 0, "Single send should not execute immediately in debounce mode")

        let exp = expectation(description: "debounce interval elapsed")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            exp.fulfill()
        }
        wait(for: [exp], timeout: 1.0)

        XCTAssertEqual(callCount, 1, "Single send should execute once after debounce interval")
    }
}
```

- [ ] **Step 2: 运行单测，确认它因缺少 `DebounceCallback` 而失败**

Run:
```bash
xcodebuild test -project Project/RYKit.xcodeproj -scheme RYKit -destination 'platform=iOS Simulator,name=iPhone 17'
```

Expected:
- 编译失败，出现 `Cannot find 'DebounceCallback' in scope` 或等价错误。

- [ ] **Step 3: 写最小实现，让默认 debounce 单测通过**

在 `Classes/Core/Combine/DebounceCallback.swift` 中写入：

```swift
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
```

- [ ] **Step 4: 重新运行单测，确认第一个测试通过**

Run:
```bash
xcodebuild test -project Project/RYKit.xcodeproj -scheme RYKit -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:RYKitTests/DebounceCallbackTests/test_singleSend_executesOnlyAfterDebounceInterval
```

Expected:
- `test_singleSend_executesOnlyAfterDebounceInterval` PASS。

- [ ] **Step 5: 提交这个最小可工作的 TDD 步骤**

```bash
git add Project/RYKitTests/DebounceCallbackTests.swift Classes/Core/Combine/DebounceCallback.swift
git commit -m "feat: add basic debounce callback"
```

### Task 2: 覆盖默认模式下“只执行最后一次”

**Files:**
- Modify: `Project/RYKitTests/DebounceCallbackTests.swift`
- Modify: `Classes/Core/Combine/DebounceCallback.swift`（预期无需修改，若测试已通过则保持不变）

- [ ] **Step 1: 增加 failing test，验证默认模式下快速连续发送只执行最后一个 closure**

在 `DebounceCallbackTests` 中追加：

```swift
func test_rapidSends_executeOnlyLatestClosureInDefaultMode() {
    var received: [String] = []
    let callback = DebounceCallback(interval: .milliseconds(120))

    callback.send { received.append("A") }
    callback.send { received.append("B") }
    callback.send { received.append("C") }

    XCTAssertTrue(received.isEmpty, "Debounce should suppress immediate execution")

    let exp = expectation(description: "debounce latest closure fired")
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
        exp.fulfill()
    }
    wait(for: [exp], timeout: 1.0)

    XCTAssertEqual(received, ["C"], "Only the latest closure should run after the debounce interval")
}
```

- [ ] **Step 2: 运行新增测试，确认其先失败（如果实现有误）或验证当前实现已满足预期**

Run:
```bash
xcodebuild test -project Project/RYKit.xcodeproj -scheme RYKit -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:RYKitTests/DebounceCallbackTests/test_rapidSends_executeOnlyLatestClosureInDefaultMode
```

Expected:
- 若实现不正确则 FAIL，断言显示收到多个值或错误值。
- 若当前实现已满足预期，则此步骤证明默认 debounce 语义已被测试锁定。

- [ ] **Step 3: 如有失败，仅做最小修复；当前计划预期无需改动生产代码**

如果必须修复，目标代码应仍保持如下默认分支：

```swift
subject.debounce(for: interval, scheduler: scheduler).sink {
    $0()
}.store(in: &cancellables)
```

- [ ] **Step 4: 再次运行相关测试，确认默认模式两个测试都通过**

Run:
```bash
xcodebuild test -project Project/RYKit.xcodeproj -scheme RYKit -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:RYKitTests/DebounceCallbackTests
```

Expected:
- 当前已添加的默认模式测试全部 PASS。

- [ ] **Step 5: 提交默认模式完整语义**

```bash
git add Project/RYKitTests/DebounceCallbackTests.swift Classes/Core/Combine/DebounceCallback.swift
git commit -m "test: cover default debounce behavior"
```

### Task 3: 覆盖“首次立即执行”语义

**Files:**
- Modify: `Project/RYKitTests/DebounceCallbackTests.swift`
- Modify: `Classes/Core/Combine/DebounceCallback.swift`（若第 1 步最小实现已包含该逻辑，则此任务主要补测试）

- [ ] **Step 1: 增加 failing test，验证开启 `shouldPerformFirstImmediately` 后首次发送同步执行**

追加：

```swift
func test_firstSend_executesImmediatelyWhenEnabled() {
    var callCount = 0
    let callback = DebounceCallback(
        interval: .seconds(10),
        shouldPerformFirstImmediately: true
    )

    callback.send { callCount += 1 }

    XCTAssertEqual(callCount, 1, "First send should execute immediately when leading behavior is enabled")
}
```

- [ ] **Step 2: 增加 failing test，验证开启后单次发送不会重复执行两次**

追加：

```swift
func test_singleSend_doesNotExecuteTwiceWhenLeadingEnabled() {
    var callCount = 0
    let callback = DebounceCallback(
        interval: .milliseconds(100),
        shouldPerformFirstImmediately: true
    )

    callback.send { callCount += 1 }
    XCTAssertEqual(callCount, 1)

    let exp = expectation(description: "wait past debounce interval")
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
        exp.fulfill()
    }
    wait(for: [exp], timeout: 1.0)

    XCTAssertEqual(callCount, 1, "Single send should not be replayed by trailing debounce")
}
```

- [ ] **Step 3: 增加 failing test，验证开启后后续连续发送只 debounce 最后一次**

追加：

```swift
func test_subsequentRapidSends_debounceToLatestWhenLeadingEnabled() {
    var received: [String] = []
    let callback = DebounceCallback(
        interval: .milliseconds(120),
        shouldPerformFirstImmediately: true
    )

    callback.send { received.append("A") }
    XCTAssertEqual(received, ["A"])

    callback.send { received.append("B") }
    callback.send { received.append("C") }
    callback.send { received.append("D") }

    let exp = expectation(description: "leading mode trailing debounce settled")
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
        exp.fulfill()
    }
    wait(for: [exp], timeout: 1.0)

    XCTAssertEqual(received, ["A", "D"], "Leading mode should execute the first closure immediately and the latest later closure after debounce")
}
```

- [ ] **Step 4: 运行这三个测试，必要时只做最小修复**

Run:
```bash
xcodebuild test -project Project/RYKit.xcodeproj -scheme RYKit -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:RYKitTests/DebounceCallbackTests/test_firstSend_executesImmediatelyWhenEnabled -only-testing:RYKitTests/DebounceCallbackTests/test_singleSend_doesNotExecuteTwiceWhenLeadingEnabled -only-testing:RYKitTests/DebounceCallbackTests/test_subsequentRapidSends_debounceToLatestWhenLeadingEnabled
```

Expected:
- 三个测试全部 PASS。
- 若失败，最小修复应保持 `first()` + `dropFirst().debounce(...)` 结构，不引入额外状态机。

生产代码关键结构应为：

```swift
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
```

- [ ] **Step 5: 提交 leading 模式语义**

```bash
git add Project/RYKitTests/DebounceCallbackTests.swift Classes/Core/Combine/DebounceCallback.swift
git commit -m "feat: support leading debounce callback"
```

### Task 4: 补齐生命周期与自定义调度器测试

**Files:**
- Modify: `Project/RYKitTests/DebounceCallbackTests.swift`
- Modify: `Classes/Core/Combine/DebounceCallback.swift`（预期无需修改）

- [ ] **Step 1: 增加测试，验证实例释放后未触发的 debounce 不会继续执行**

追加：

```swift
func test_deinit_stopsPendingDebouncedExecution() {
    var callCount = 0
    var callback: DebounceCallback? = DebounceCallback(interval: .milliseconds(100))

    callback?.send { callCount += 1 }
    callback = nil

    let exp = expectation(description: "wait after dealloc")
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
        exp.fulfill()
    }
    wait(for: [exp], timeout: 1.0)

    XCTAssertEqual(callCount, 0, "Pending debounced work should not fire after instance deallocation")
}
```

- [ ] **Step 2: 增加测试，验证自定义 scheduler 下默认模式仍然生效**

追加：

```swift
func test_defaultMode_worksWithCustomScheduler() {
    let queue = DispatchQueue(label: "test.debounce")
    let lock = NSLock()
    var callCount = 0
    let callback = DebounceCallback(interval: .milliseconds(80), scheduler: queue)

    callback.send {
        lock.lock()
        callCount += 1
        lock.unlock()
    }

    Thread.sleep(forTimeInterval: 0.03)
    lock.lock()
    let earlyCount = callCount
    lock.unlock()
    XCTAssertEqual(earlyCount, 0, "Default debounce mode should not execute immediately on custom scheduler")

    let exp = expectation(description: "custom scheduler debounce settled")
    DispatchQueue.global().asyncAfter(deadline: .now() + 0.2) {
        exp.fulfill()
    }
    wait(for: [exp], timeout: 1.0)

    lock.lock()
    let finalCount = callCount
    lock.unlock()
    XCTAssertEqual(finalCount, 1, "Debounced closure should eventually execute on custom scheduler")
}
```

- [ ] **Step 3: 运行完整测试文件，确认所有 DebounceCallback 测试都通过**

Run:
```bash
xcodebuild test -project Project/RYKit.xcodeproj -scheme RYKit -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:RYKitTests/DebounceCallbackTests
```

Expected:
- `DebounceCallbackTests` 全部 PASS。
- 无额外 warning 或异步超时失败。

- [ ] **Step 4: 目检最终生产代码，确认公开 API 与 spec 完全一致**

应确认 `Classes/Core/Combine/DebounceCallback.swift` 最终仍为：

```swift
import Combine
import Foundation

public class DebounceCallback {

    private let subject: PassthroughSubject<() -> Void, Never>
    private var cancellables = Set<AnyCancellable>()

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

    public func send(_ closure: @escaping () -> Void) {
        subject.send(closure)
    }
}
```

- [ ] **Step 5: 提交完整实现**

```bash
git add Project/RYKitTests/DebounceCallbackTests.swift Classes/Core/Combine/DebounceCallback.swift
git commit -m "feat: add debounce callback"
```

## Self-Review

- **Spec coverage:**
  - 默认 debounce 语义：Task 1 + Task 2
  - `shouldPerformFirstImmediately` 行为：Task 3
  - “单次不会执行两次”边界：Task 3
  - 生命周期与 scheduler 兼容性：Task 4
- **Placeholder scan:**
  - 计划中的代码、文件路径、命令、预期结果均已具体写出，无 TBD/TODO。
- **Type consistency:**
  - 全文统一使用 `DebounceCallback`、`shouldPerformFirstImmediately`、`send(_:)`；与 spec 一致。
