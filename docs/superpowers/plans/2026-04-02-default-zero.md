# Default.Zero 自动数值零值 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 为 `DefaultValue` 增加统一的 `@Default.Zero` 数值零值入口，支持 `Int`、`Float`、`Double`、`Decimal` 基于属性类型自动推断零值；同时将现有 `IntZero`/`FloatZero`/`DoubleZero`/`DecimalZero` 收敛为指向新入口的 deprecated compatibility aliases。

**Architecture:** 在 `DefaultValue.swift` 中新增 `ZeroValue` 协议与泛型 `ZeroProvider<T>`，用 `ZeroValue where Self: Numeric` 提供统一零值默认实现，并通过 `Int` / `Float` / `Double` / `Decimal` 的显式遵守限制当前支持范围。`Default.Zero` 作为唯一新入口；旧的四个 Zero API 保留为 deprecated typealias，旧的按类型 zero providers 删除。现有解码与类型转换管线保持不变。

**Tech Stack:** Swift, XCTest, property wrappers, Codable

---

## File Structure

- Modify: `Classes/Core/Codable/ValueWrapper/DefaultValue.swift`
  - 新增 `ZeroValue` 协议
  - 添加 `ZeroValue where Self: Numeric` 默认实现
  - 为 `Int` / `Float` / `Double` / `Decimal` 添加显式 `ZeroValue` 遵守声明
  - 新增 `ZeroProvider<T>`
  - 在 `Default` 中新增统一入口 `Zero`
  - 将现有 `IntZero` / `FloatZero` / `DoubleZero` / `DecimalZero` 改为 deprecated aliases
  - 删除旧的按类型 zero providers

- Modify: `Project/RYKitTests/ValueWrapperTests.swift`
  - 新增 `ZeroModel`
  - 新增语法与默认值回退测试
  - 新增解码行为测试
  - 保留并回归现有 `DefaultValue` 测试

- Verify/Read: `docs/superpowers/specs/2026-04-02-default-zero-design.md`
  - 作为实现依据，确保计划覆盖 spec 要求

### Task 1: 验证 `@Default.Zero` 语法可行性

**Files:**
- Modify: `Project/RYKitTests/ValueWrapperTests.swift`
- Test: `Project/RYKitTests/ValueWrapperTests.swift`
- Reference: `docs/superpowers/specs/2026-04-02-default-zero-design.md`

- [ ] **Step 1: 在测试文件中添加最小 `ZeroModel` 定义，先只验证编译与默认值语义**

```swift
private struct ZeroModel: Codable {
    @Default.Zero var intValue: Int
    @Default.Zero var floatValue: Float
    @Default.Zero var doubleValue: Double
    @Default.Zero var decimalValue: Decimal
}
```

将其插入到 `ValueWrapperTests.swift` 现有测试模型定义区域，放在 `FloatDictionaryModel` 之后、`DefaultValueTests` 之前，保持测试文件结构一致。

- [ ] **Step 2: 添加一个最小失败测试，要求 `ZeroModel` 在空 JSON 下解码为零值**

```swift
func test_decode_zeroModel_withMissingKey_usesZeroDefaults() throws {
    let json = "{}"
    let model = try decode(ZeroModel.self, from: json)

    XCTAssertEqual(model.intValue, 0)
    XCTAssertEqual(model.floatValue, 0, accuracy: 0.0001)
    XCTAssertEqual(model.doubleValue, 0, accuracy: 0.0001)
    XCTAssertEqual(model.decimalValue, Decimal.zero)
}
```

这个测试的第一目的不是行为覆盖，而是强迫编译器接受 `@Default.Zero` 写法。

- [ ] **Step 3: 运行单测，确认当前分支处于“编译失败或测试失败”的红灯状态**

Run:
```bash
xcodebuild test -scheme RYKit -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:RYKitTests/DefaultValueTests/test_decode_zeroModel_withMissingKey_usesZeroDefaults
```

Expected:
- 如果语法不成立：编译失败，出现泛型无法推断或 `Default.Zero` 未定义相关错误
- 如果语法成立但实现未完成：测试失败，零值不正确或找不到相应类型

- [ ] **Step 4: 若是编译失败，记录具体错误并确认是否仍属于方案 A 可解空间**

若错误是 `Type 'Default' has no member 'Zero'`，继续下一任务实现。

若错误是 `Generic parameter could not be inferred` 或 property wrapper 无法从属性类型推断泛型，则停止执行后续实现，说明 spec 的核心语法假设不成立，需要回到设计阶段调整方案。

- [ ] **Step 5: 提交测试脚手架（仅在语法成立且测试已进入红灯状态时提交）**

```bash
git add Project/RYKitTests/ValueWrapperTests.swift
git commit -m "test: add Default.Zero syntax coverage"
```

### Task 2: 实现统一零值协议与 `Default.Zero`

**Files:**
- Modify: `Classes/Core/Codable/ValueWrapper/DefaultValue.swift`
- Test: `Project/RYKitTests/ValueWrapperTests.swift`

- [ ] **Step 1: 在 `DefaultValue.swift` 中新增 `ZeroValue` 协议定义**

将以下代码加在 `Initializable` 协议附近，保持默认值相关协议集中：

```swift
public protocol ZeroValue {
    static var zeroValue: Self { get }
}
```

不要复用 `Initializable`，因为 `init()` 的语义不是“数值零值”。

- [ ] **Step 2: 为四种数值类型补充 `ZeroValue` 默认实现与显式遵守声明**

在现有基础类型扩展区域添加：

```swift
public extension ZeroValue where Self: Numeric {
    static var zeroValue: Self { .zero }
}

extension Int: ZeroValue {}
extension Float: ZeroValue {}
extension Double: ZeroValue {}
extension Decimal: ZeroValue {}
```

用 `Numeric` 条件扩展统一提供零值，避免为每个类型重复实现 `zeroValue`，同时通过显式遵守把支持范围限制在当前这四类数值类型。

- [ ] **Step 3: 新增泛型 `ZeroProvider<T>`，复用现有 `DefaultValueProvider` 体系**

将以下定义加入 `DefaultValueProviders` 邻近区域，但不要嵌套在 `DefaultValueProviders` 内部，以避免与现有按类型 provider 混淆：

```swift
public enum ZeroProvider<T: Codable & ZeroValue>: DefaultValueProvider {
    public static var `default`: T { T.zeroValue }
}
```

- [ ] **Step 4: 在 `Default` 中增加统一入口 `Zero`，并将旧入口改为 deprecated aliases**

在 `Default` 结构体的 typealias 区域加入：

```swift
public typealias Zero<T: Codable & ZeroValue> = DefaultValue<ZeroProvider<T>>

@available(*, deprecated, message: "Use @Default.Zero instead.")
public typealias IntZero = Zero<Int>
@available(*, deprecated, message: "Use @Default.Zero instead.")
public typealias FloatZero = Zero<Float>
@available(*, deprecated, message: "Use @Default.Zero instead.")
public typealias DoubleZero = Zero<Double>
@available(*, deprecated, message: "Use @Default.Zero instead.")
public typealias DecimalZero = Zero<Decimal>
```

同时删除 `DefaultValueProviders` 中旧的按类型 zero providers，避免保留两套底层实现。

- [ ] **Step 5: 运行刚才的单测，确认 `@Default.Zero` 最小用例通过**

Run:
```bash
xcodebuild test -scheme RYKit -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:RYKitTests/DefaultValueTests/test_decode_zeroModel_withMissingKey_usesZeroDefaults
```

Expected: PASS

- [ ] **Step 6: 提交最小实现**

```bash
git add Classes/Core/Codable/ValueWrapper/DefaultValue.swift Project/RYKitTests/ValueWrapperTests.swift
git commit -m "feat: add Default.Zero provider"
```

### Task 3: 补齐 `Default.Zero` 行为测试

**Files:**
- Modify: `Project/RYKitTests/ValueWrapperTests.swift`
- Test: `Project/RYKitTests/ValueWrapperTests.swift`

- [ ] **Step 1: 为 `ZeroModel` 添加同类型解码测试**

将以下测试加入 `DefaultValueTests`：

```swift
func test_decode_zeroModel_withMatchingTypes_succeeds() throws {
    let json = """
    {"intValue": 42, "floatValue": 2.5, "doubleValue": 3.14, "decimalValue": 99.99}
    """
    let model = try decode(ZeroModel.self, from: json)

    XCTAssertEqual(model.intValue, 42)
    XCTAssertEqual(model.floatValue, 2.5, accuracy: 0.0001)
    XCTAssertEqual(model.doubleValue, 3.14, accuracy: 0.001)
    XCTAssertEqual(model.decimalValue, Decimal(string: "99.99"))
}
```

- [ ] **Step 2: 为 `ZeroModel` 添加 `null` 回退测试**

```swift
func test_decode_zeroModel_withNullValues_usesZeroDefaults() throws {
    let json = """
    {"intValue": null, "floatValue": null, "doubleValue": null, "decimalValue": null}
    """
    let model = try decode(ZeroModel.self, from: json)

    XCTAssertEqual(model.intValue, 0)
    XCTAssertEqual(model.floatValue, 0, accuracy: 0.0001)
    XCTAssertEqual(model.doubleValue, 0, accuracy: 0.0001)
    XCTAssertEqual(model.decimalValue, Decimal.zero)
}
```

- [ ] **Step 3: 为 `ZeroModel` 添加跨类型转换测试，验证沿用现有转换能力**

```swift
func test_decode_zeroModel_withConvertibleValues_converts() throws {
    let json = """
    {"intValue": "12", "floatValue": "2.5", "doubleValue": 7, "decimalValue": "8.75"}
    """
    let model = try decode(ZeroModel.self, from: json)

    XCTAssertEqual(model.intValue, 12)
    XCTAssertEqual(model.floatValue, 2.5, accuracy: 0.0001)
    XCTAssertEqual(model.doubleValue, 7, accuracy: 0.0001)
    XCTAssertEqual(model.decimalValue, Decimal(string: "8.75"))
}
```

- [ ] **Step 4: 运行仅针对新增 `ZeroModel` 的测试，确认行为全部通过**

Run:
```bash
xcodebuild test -scheme RYKit -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:RYKitTests/DefaultValueTests/test_decode_zeroModel_withMissingKey_usesZeroDefaults -only-testing:RYKitTests/DefaultValueTests/test_decode_zeroModel_withMatchingTypes_succeeds -only-testing:RYKitTests/DefaultValueTests/test_decode_zeroModel_withNullValues_usesZeroDefaults -only-testing:RYKitTests/DefaultValueTests/test_decode_zeroModel_withConvertibleValues_converts
```

Expected: PASS

- [ ] **Step 5: 提交行为测试补充**

```bash
git add Project/RYKitTests/ValueWrapperTests.swift
git commit -m "test: cover Default.Zero decoding behavior"
```

### Task 4: 运行回归验证并确认兼容性

**Files:**
- Modify: `Project/RYKitTests/ValueWrapperTests.swift`
- Test: `Project/RYKitTests/ValueWrapperTests.swift`
- Reference: `Classes/Core/Codable/ValueWrapper/DefaultValue.swift`

- [ ] **Step 1: 为统一零值实现补充协议默认实现与兼容别名验证测试**

新增测试覆盖：

```swift
func test_zeroValue_numericDefaultImplementation_usesZeroProviderDefaults() {
    XCTAssertEqual(ZeroProvider<Int>.default, 0)
    XCTAssertEqual(ZeroProvider<Float>.default, 0, accuracy: 0.0001)
    XCTAssertEqual(ZeroProvider<Double>.default, 0, accuracy: 0.0001)
    XCTAssertEqual(ZeroProvider<Decimal>.default, Decimal.zero)
}

func test_deprecatedZeroAliases_useZeroProviderDefaults() {
    XCTAssertEqual(Default.IntZero().wrappedValue, 0)
    XCTAssertEqual(Default.FloatZero().wrappedValue, 0, accuracy: 0.0001)
    XCTAssertEqual(Default.DoubleZero().wrappedValue, 0, accuracy: 0.0001)
    XCTAssertEqual(Default.DecimalZero().wrappedValue, Decimal.zero)
}
```

并将原先直接依赖 `DefaultValueProviders.IntZero` / `FloatZero` 等旧 provider 的测试改为断言 deprecated aliases 的行为，以匹配当前实现。

- [ ] **Step 2: 运行 `DefaultValueTests` 相关测试，确认旧 API 未回归**

Run:
```bash
xcodebuild test -scheme RYKit -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:RYKitTests/DefaultValueTests
```

Expected: PASS

重点确认以下既有测试仍通过：
- `test_decode_withMatchingType_succeeds`
- `test_decode_withMissingKey_usesDefault`
- `test_decode_withNullValue_usesDefault`
- `test_decode_stringToFloat_converts`
- `test_decode_floatArray_convertsElements`
- `test_decode_floatDictionary_convertsValues`

- [ ] **Step 2: 如项目测试成本可接受，运行完整测试套件做最终回归**

Run:
```bash
xcodebuild test -scheme RYKit -destination 'platform=iOS Simulator,name=iPhone 16'
```

Expected: PASS

若完整测试耗时过高，但 `DefaultValueTests` 已完整覆盖当前变更面，可在执行记录中注明已运行的范围与理由。

- [ ] **Step 3: 检查工作区差异，确认仅包含实现与测试文件修改**

Run:
```bash
git status --short
git diff -- Classes/Core/Codable/ValueWrapper/DefaultValue.swift Project/RYKitTests/ValueWrapperTests.swift
```

Expected:
- 仅看到 `DefaultValue.swift` 与 `ValueWrapperTests.swift` 的目标修改
- 无无关文件改动

- [ ] **Step 4: 提交最终兼容性验证结果**

```bash
git add Classes/Core/Codable/ValueWrapper/DefaultValue.swift Project/RYKitTests/ValueWrapperTests.swift
git commit -m "test: verify Default.Zero compatibility"
```

## Self-Review

- **Spec coverage:**
  - `Default.Zero` 统一入口：Task 2
  - 仅支持数值零值：Task 2 中 `ZeroValue` 只实现四种数值类型
  - 保持解码转换逻辑不变：Task 2 明确仅新增协议/provider/typealias，不重写转换链路
  - 语法可行性验证：Task 1
  - 行为测试与兼容性：Task 3、Task 4

- **Placeholder scan:**
  - 已避免使用 TBD/TODO/“适当处理”等空泛描述
  - 所有代码步骤都给出明确代码或命令

- **Type consistency:**
  - 统一使用 `ZeroValue`、`ZeroProvider<T>`、`Default.Zero`、`ZeroModel`
  - 所有测试名称与模型名称前后一致

## Execution Handoff

Plan complete and saved to `docs/superpowers/plans/2026-04-02-default-zero.md`. Two execution options:

**1. Subagent-Driven (recommended)** - I dispatch a fresh subagent per task, review between tasks, fast iteration

**2. Inline Execution** - Execute tasks in this session using executing-plans, batch execution with checkpoints

Which approach?
