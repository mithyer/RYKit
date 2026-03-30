# DebounceCallback Design

**目标**

在 `RYKitCore` 的 `Combine` 目录下新增一个与 `ThrottleCallback` 风格一致的 `DebounceCallback`，用于包装闭包回调的防抖执行逻辑。

**设计范围**

本次仅设计一个新的回调包装类型：`DebounceCallback`。
不涉及 `ThrottleCallback` 的行为修改，不引入额外配置项，不扩展到参数化回调或可取消任务能力。

## 一、对外接口

建议公开接口如下：

```swift
public class DebounceCallback {
    public init<S: Scheduler>(
        interval: S.SchedulerTimeType.Stride,
        scheduler: S = RunLoop.main,
        shouldPerformFirstImmediately: Bool = false
    )

    public func send(_ closure: @escaping () -> Void)
}
```

### 接口说明

- `interval`
  - 防抖时间窗口。
- `scheduler`
  - 防抖回调派发所使用的调度器，默认 `RunLoop.main`。
- `shouldPerformFirstImmediately`
  - 是否在第一次 `send()` 时立即执行，默认 `false`。
- `send(_:)`
  - 发送一个待执行闭包，由内部规则决定何时执行。

## 二、行为定义

### 模式 A：标准 debounce（默认）
当 `shouldPerformFirstImmediately == false` 时：

- 每次 `send()` 都会替换掉上一次尚未触发的闭包。
- 仅在最后一次发送后，经过完整静默窗口，执行最后那个闭包。
- 单次 `send()` 不会立即执行，而是在 `interval` 到期后执行。

#### 示例

- `t=0ms` -> `send(A)`
- `t=100ms` -> `send(B)`
- `t=200ms` -> `send(C)`
- `interval = 300ms`

预期：
- `A` 不执行
- `B` 不执行
- `C` 在最后一次发送后的静默期结束时执行一次

### 模式 B：首次立即执行 + 后续 debounce
当 `shouldPerformFirstImmediately == true` 时：

- 第一次 `send()` 的闭包立即执行。
- 从第二次开始，后续发送进入标准 debounce 流程。
- 在连续发送场景中，后续仍然只保留最后一个闭包，在静默窗口结束后执行。

#### 示例

- `t=0ms` -> `send(A)`，立即执行 `A`
- `t=100ms` -> `send(B)`
- `t=200ms` -> `send(C)`
- `interval = 300ms`

预期：
- `A` 立即执行
- `B` 不执行
- `C` 在静默期结束后执行一次

### 关键边界
当 `shouldPerformFirstImmediately == true` 且只调用一次时：

- `t=0ms` -> `send(A)`

预期：
- `A` 只执行一次
- 不应在 debounce 窗口结束后再次重复执行 `A`

这是本次设计中必须明确保证的语义，避免单次调用被执行两次。

## 三、实现策略

建议沿用 `ThrottleCallback` 的组合式思路，以 `PassthroughSubject<() -> Void, Never>` 为事件源，并根据配置构建不同的 Combine 管道。

### 情况 1：`shouldPerformFirstImmediately == false`
使用单条管道：

```swift
subject
    .debounce(for: interval, scheduler: scheduler)
    .sink { $0() }
```

含义：
- 所有事件统一走标准 debounce。
- 实现最直接，也最符合默认行为语义。

### 情况 2：`shouldPerformFirstImmediately == true`
使用两条管道：

```swift
subject
    .first()
    .sink { $0() }

subject
    .dropFirst()
    .debounce(for: interval, scheduler: scheduler)
    .sink { $0() }
```

含义：
- 第一条管道保证首次事件立即执行。
- 第二条管道只处理后续事件，确保 trailing debounce 行为。
- 因为后续管道显式 `dropFirst()`，所以首次事件不会再次被 debounce 流程消费。

### 为什么不用手写状态机
不建议引入额外状态变量去手动判断“是否首次发送”，原因是：

- 当前需求简单，Combine 现有操作符已足够表达。
- 双管道方案与现有 `ThrottleCallback` 的设计风格一致。
- 更少的手写状态意味着更低的维护成本与更清晰的行为边界。

## 四、测试设计

实现阶段应采用 TDD，至少覆盖以下行为：

1. **默认模式：连续调用时只执行最后一次**
2. **默认模式：单次调用不会立即执行，而会在 debounce 窗口结束后执行**
3. **首次立即执行模式：第一次调用立即执行**
4. **首次立即执行模式：后续连续调用只会 debounce 出最后一次**
5. **首次立即执行模式：单次调用不会被执行两次**

### 推荐测试组织方式

建议新增独立测试文件：
- `Project/RYKitTests/DebounceCallbackTests.swift`

并参考现有 `ThrottleCallbackTests.swift` 的测试风格，保持：
- 相同的 XCTest 组织方式
- 相同或相近的异步等待手法
- 相似的命名粒度与断言风格

## 五、兼容性与影响范围

### 影响范围
本设计仅新增：
- `Classes/Core/Combine/DebounceCallback.swift`
- 对应测试文件

不需要修改：
- `ThrottleCallback.swift`
- `Package.swift`
- `RYKit.podspec`

因为 `RYKitCore` 已通过目录级 source inclusion 暴露 `Classes/Core/**/*`，新增文件会自动纳入现有模块。

### 向后兼容性
本次为新增能力，不破坏任何既有 API，因此不存在向后兼容风险。

## 六、最终建议

采用以下最终方案：

- 新增 `DebounceCallback`
- 默认行为为标准 debounce
- 新增 `shouldPerformFirstImmediately: Bool = false`
- 当其为 `true` 时，语义为“首次立即执行，后续 trailing debounce”
- 内部实现延续 `ThrottleCallback` 的双管道组合风格
- 实现阶段通过 TDD 锁定 5 个核心行为测试
