# Default.Empty Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 为 `DefaultValue` 增加统一的 `@Default.Empty` 空值入口，支持 `String`、`Array`、`Dictionary`、`Set` 基于属性类型自动推断空值，并将旧的 `*Empty` API 收敛为 deprecated compatibility aliases。

**Architecture:** 在 `DefaultValue.swift` 中新增 `EmptyValue` 协议与泛型 `EmptyProvider<T>`，用 `RangeReplaceableCollection` 条件扩展为 `String`、`Array`、`Set` 提供统一空值默认实现，并为 `Dictionary` 单独补充 `emptyValue`。`Default.Empty` 作为唯一新入口；旧的 `StringEmpty` / `ArrayEmpty` / `DicEmpty` / `SetEmpty` 保留为 deprecated typealias，旧的按类型 empty providers 删除。现有解码与类型转换管线保持不变。

**Tech Stack:** Swift, XCTest, property wrappers, Codable

---

## File Structure

- Modify: `Classes/Core/Codable/ValueWrapper/DefaultValue.swift`
  - 新增 `EmptyValue` 协议
  - 添加 `EmptyValue where Self: RangeReplaceableCollection` 默认实现
  - 为 `String` / `Array` / `Set` / `Dictionary` 添加显式 `EmptyValue` 遵守声明
  - 为 `Dictionary` 添加 `emptyValue` 实现
  - 新增 `EmptyProvider<T>`
  - 在 `Default` 中新增统一入口 `Empty`
  - 将现有 `StringEmpty` / `ArrayEmpty` / `DicEmpty` 改为 deprecated aliases
  - 新增并同时 deprecated `SetEmpty`
  - 删除旧的按类型 empty providers

- Modify: `Project/RYKitTests/ValueWrapperTests.swift`
  - 新增 `EmptyModel`
  - 新增 `Set` 默认值与解码测试
  - 新增 `Default.Empty` 语法与行为测试
  - 新增 compatibility alias 测试
  - 将旧 provider 直连断言改为新 aliases 断言

- Verify/Read: `docs/superpowers/specs/2026-04-02-default-empty-design.md`
  - 作为实现依据，确保计划覆盖 spec 要求

### Task 1: 验证 `@Default.Empty` 语法可行性

**Files:**
- Modify: `Project/RYKitTests/ValueWrapperTests.swift`
- Test: `Project/RYKitTests/ValueWrapperTests.swift`
- Reference: `docs/superpowers/specs/2026-04-02-default-empty-design.md`

- [ ] **Step 1: 在测试文件中添加最小 `EmptyModel` 定义，先只验证编译与默认值语义**

```swift
private struct EmptyModel: Codable {
    @Default.Empty var name: String
    @Default.Empty var tags: [String]
    @Default.Empty var mapping: [String: Int]
    @Default.Empty var ids: Set<Int>
}
```

将其插入到 `ValueWrapperTests.swift` 现有测试模型定义区域，放在 `ZeroModel` 之后、`DefaultValueTests` 之前，保持测试文件结构一致。

- [ ] **Step 2: 添加一个最小失败测试，要求 `EmptyModel` 在空 JSON 下解码为空值**

```swift
func test_decode_emptyModel_withMissingKey_usesEmptyDefaults() throws {
    let json = "{}"
    let model = try decode(EmptyModel.self, from: json)

    XCTAssertEqual(model.name, "")
    XCTAssertEqual(model.tags, [])
    XCTAssertEqual(model.mapping, [:])
    XCTAssertEqual(model.ids, Set<Int>())
}
```

这个测试的第一目的不是行为覆盖，而是强迫编译器接受 `@Default.Empty` 写法。

- [ ] **Step 3: 运行单测，确认当前分支处于“编译失败或测试失败”的红灯状态**

Run:
```bash
xcodebuild test -project "/Users/ray/Documents/projects/rykit/Project/RYKit.xcodeproj" -scheme RYKitTests -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.2' -only-testing:RYKitTests/DefaultValueTests/test_decode_emptyModel_withMissingKey_usesEmptyDefaults
```

Expected:
- 如果语法不成立：编译失败，出现泛型无法推断或 `Default.Empty` 未定义相关错误
- 如果语法成立但实现未完成：测试失败，空值不正确或找不到相应类型

- [ ] **Step 4: 若是编译失败，记录具体错误并确认是否仍属于方案 A 可解空间**

若错误是 `Type 'Default' has no member 'Empty'`，继续下一任务实现。

若错误是 `Generic parameter could not be inferred` 或 property wrapper 无法从属性类型推断泛型，则停止执行后续实现，说明 spec 的核心语法假设不成立，需要回到设计阶段调整方案。

- [ ] **Step 5: 提交测试脚手架（仅在语法成立且测试已进入红灯状态时提交）**

```bash
git add Project/RYKitTests/ValueWrapperTests.swift
git commit -m "test: add Default.Empty syntax coverage"
```

### Task 2: 实现统一空值协议与 `Default.Empty`

**Files:**
- Modify: `Classes/Core/Codable/ValueWrapper/DefaultValue.swift`
- Test: `Project/RYKitTests/ValueWrapperTests.swift`

- [ ] **Step 1: 在 `DefaultValue.swift` 中新增 `EmptyValue` 协议定义**

将以下代码加在 `ZeroValue` 协议附近，保持默认值相关协议集中：

```swift
public protocol EmptyValue {
    static var emptyValue: Self { get }
}
```

不要复用 `Initializable`，因为 `init()` 的语义不是“明确空值”。

- [ ] **Step 2: 为 `RangeReplaceableCollection` 提供统一空值默认实现，并为支持类型补充显式遵守声明**

在现有基础类型扩展区域添加：

```swift
public extension EmptyValue where Self: RangeReplaceableCollection {
    static var emptyValue: Self { Self() }
}

extension String: EmptyValue {}
extension Array: EmptyValue {}
extension Set: EmptyValue {}
```

用条件扩展统一提供 `String`、`Array`、`Set` 的空值，避免为每个类型重复实现 `emptyValue`。

- [ ] **Step 3: 为 `Dictionary` 单独补充 `EmptyValue` 实现**

在同一区域添加：

```swift
extension Dictionary: EmptyValue {
    public static var emptyValue: [Key: Value] { [:] }
}
```

不要尝试把 `Dictionary` 塞进 `RangeReplaceableCollection` 路径；单独实现更直接，也更符合 spec。

- [ ] **Step 4: 新增泛型 `EmptyProvider<T>`，复用现有 `DefaultValueProvider` 体系**

将以下定义加入 `ZeroProvider<T>` 邻近区域，但不要嵌套在 `DefaultValueProviders` 内部：

```swift
public enum EmptyProvider<T: Codable & EmptyValue>: DefaultValueProvider {
    public static var `default`: T { T.emptyValue }
}
```

- [ ] **Step 5: 在 `Default` 中增加统一入口 `Empty`，并将旧入口改为 deprecated aliases**

在 `Default` 结构体的 typealias 区域加入：

```swift
public typealias Empty<T: Codable & EmptyValue> = DefaultValue<EmptyProvider<T>>

@available(*, deprecated, message: "Use @Default.Empty instead.")
public typealias StringEmpty = Empty<String>
@available(*, deprecated, message: "Use @Default.Empty instead.")
public typealias ArrayEmpty<A: Codable & RangeReplaceableCollection> = Empty<A>
@available(*, deprecated, message: "Use @Default.Empty instead.")
public typealias DicEmpty<K: Hashable & Codable, V: Codable> = Empty<[K: V]>
@available(*, deprecated, message: "Use @Default.Empty instead.")
public typealias SetEmpty<A: Hashable & Codable> = Empty<Set<A>>
```

同时删除 `DefaultValueProviders` 中旧的 `StringEmpty` / `ArrayEmpty` / `DicEmpty` 实现，避免保留两套底层逻辑。

- [ ] **Step 6: 运行刚才的单测，确认 `@Default.Empty` 最小用例通过**

Run:
```bash
xcodebuild test -project "/Users/ray/Documents/projects/rykit/Project/RYKit.xcodeproj" -scheme RYKitTests -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.2' -only-testing:RYKitTests/DefaultValueTests/test_decode_emptyModel_withMissingKey_usesEmptyDefaults
```

Expected: PASS

- [ ] **Step 7: 提交最小实现**

```bash
git add Classes/Core/Codable/ValueWrapper/DefaultValue.swift Project/RYKitTests/ValueWrapperTests.swift
git commit -m "feat: add Default.Empty provider"
```

### Task 3: 补齐 `Default.Empty` 行为测试

**Files:**
- Modify: `Project/RYKitTests/ValueWrapperTests.swift`
- Test: `Project/RYKitTests/ValueWrapperTests.swift`

- [ ] **Step 1: 为 `EmptyModel` 添加同类型解码测试**

将以下测试加入 `DefaultValueTests`：

```swift
func test_decode_emptyModel_withMatchingTypes_succeeds() throws {
    let json = """
    {"name": "ray", "tags": ["swift", "codable"], "mapping": {"a": 1, "b": 2}, "ids": [1, 2, 3]}
    """
    let model = try decode(EmptyModel.self, from: json)

    XCTAssertEqual(model.name, "ray")
    XCTAssertEqual(model.tags, ["swift", "codable"])
    XCTAssertEqual(model.mapping, ["a": 1, "b": 2])
    XCTAssertEqual(model.ids, Set([1, 2, 3]))
}
```

- [ ] **Step 2: 为 `EmptyModel` 添加 `null` 回退测试**

```swift
func test_decode_emptyModel_withNullValues_usesEmptyDefaults() throws {
    let json = """
    {"name": null, "tags": null, "mapping": null, "ids": null}
    """
    let model = try decode(EmptyModel.self, from: json)

    XCTAssertEqual(model.name, "")
    XCTAssertEqual(model.tags, [])
    XCTAssertEqual(model.mapping, [:])
    XCTAssertEqual(model.ids, Set<Int>())
}
```

- [ ] **Step 3: 为 `Set` 增加独立默认值与解码断言**

新增一个最小模型并测试：

```swift
private struct SetContainerModel: Codable {
    @Default.Empty var ids: Set<Int>
}

func test_decode_setContainerModel_withMatchingType_succeeds() throws {
    let json = """
    {"ids": [3, 1, 3, 2]}
    """
    let model = try decode(SetContainerModel.self, from: json)

    XCTAssertEqual(model.ids, Set([1, 2, 3]))
}
```

这一步确保 `Set` 不只是“默认值可用”，而是与现有 Codable 解码组合后仍然行为正确。

- [ ] **Step 4: 为统一空值实现补充 provider 与兼容别名验证测试**

加入以下测试：

```swift
func test_emptyValue_defaultImplementations_useEmptyProviderDefaults() {
    XCTAssertEqual(EmptyProvider<String>.default, "")
    XCTAssertEqual(EmptyProvider<[Int]>.default, [])
    XCTAssertEqual(EmptyProvider<[String: Int]>.default, [:])
    XCTAssertEqual(EmptyProvider<Set<Int>>.default, Set<Int>())
}

func test_deprecatedEmptyAliases_useEmptyProviderDefaults() {
    XCTAssertEqual(Default.StringEmpty().wrappedValue, "")
    XCTAssertEqual(Default.ArrayEmpty<[Int]>().wrappedValue, [])
    XCTAssertEqual(Default.DicEmpty<String, Int>().wrappedValue, [:])
    XCTAssertEqual(Default.SetEmpty<Int>().wrappedValue, Set<Int>())
}
```

- [ ] **Step 5: 将旧 provider 直连断言改为 alias 行为断言**

把测试文件中依赖旧 provider 实现细节的断言替换为：

```swift
func test_providers_stringEmpty_default() {
    XCTAssertEqual(Default.StringEmpty().wrappedValue, "")
}

func test_providers_arrayEmpty_default() throws {
    XCTAssertEqual(Default.ArrayEmpty<[Int]>().wrappedValue, [])
    XCTAssertEqual(Default.ArrayEmpty<[String]>().wrappedValue, [])
}

func test_providers_dicEmpty_default() {
    XCTAssertEqual(Default.DicEmpty<String, Int>().wrappedValue, [:])
}
```

如果原文件没有完整对应测试，就按同样命名风格新增，避免继续依赖已删除的旧 provider 类型。

- [ ] **Step 6: 运行仅针对新增 `EmptyModel` 与 alias 覆盖的测试，确认行为全部通过**

Run:
```bash
xcodebuild test -project "/Users/ray/Documents/projects/rykit/Project/RYKit.xcodeproj" -scheme RYKitTests -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.2' \
  -only-testing:RYKitTests/DefaultValueTests/test_decode_emptyModel_withMissingKey_usesEmptyDefaults \
  -only-testing:RYKitTests/DefaultValueTests/test_decode_emptyModel_withMatchingTypes_succeeds \
  -only-testing:RYKitTests/DefaultValueTests/test_decode_emptyModel_withNullValues_usesEmptyDefaults \
  -only-testing:RYKitTests/DefaultValueTests/test_decode_setContainerModel_withMatchingType_succeeds \
  -only-testing:RYKitTests/DefaultValueTests/test_emptyValue_defaultImplementations_useEmptyProviderDefaults \
  -only-testing:RYKitTests/DefaultValueTests/test_deprecatedEmptyAliases_useEmptyProviderDefaults
```

Expected: PASS

- [ ] **Step 7: 提交行为测试补充**

```bash
git add Project/RYKitTests/ValueWrapperTests.swift
git commit -m "test: cover Default.Empty behavior"
```

### Task 4: 运行回归验证并确认兼容性

**Files:**
- Modify: `Project/RYKitTests/ValueWrapperTests.swift`
- Test: `Project/RYKitTests/ValueWrapperTests.swift`
- Reference: `Classes/Core/Codable/ValueWrapper/DefaultValue.swift`

- [ ] **Step 1: 运行 `DefaultValueTests` 相关测试，确认旧 API 未回归**

Run:
```bash
xcodebuild test -project "/Users/ray/Documents/projects/rykit/Project/RYKit.xcodeproj" -scheme RYKitTests -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.2' -only-testing:RYKitTests/DefaultValueTests
```

Expected: PASS

重点确认以下既有与新增测试仍通过：
- `test_decode_withMatchingType_succeeds`
- `test_decode_withMissingKey_usesDefault`
- `test_decode_withNullValue_usesDefault`
- `test_decode_floatArray_convertsElements`
- `test_decode_floatDictionary_convertsValues`
- `test_decode_zeroModel_withMissingKey_usesZeroDefaults`
- `test_decode_emptyModel_withMissingKey_usesEmptyDefaults`
- `test_deprecatedEmptyAliases_useEmptyProviderDefaults`

- [ ] **Step 2: 检查工作区差异，确认仅包含实现、测试与必要文档文件修改**

Run:
```bash
git status --short
git diff -- Classes/Core/Codable/ValueWrapper/DefaultValue.swift Project/RYKitTests/ValueWrapperTests.swift docs/superpowers/specs/2026-04-02-default-empty-design.md docs/superpowers/plans/2026-04-02-default-empty.md
```

Expected:
- 仅看到 `DefaultValue.swift`、`ValueWrapperTests.swift`、spec、plan 的目标修改
- 无无关文件改动

- [ ] **Step 3: 提交最终兼容性验证结果**

```bash
git add Classes/Core/Codable/ValueWrapper/DefaultValue.swift Project/RYKitTests/ValueWrapperTests.swift docs/superpowers/plans/2026-04-02-default-empty.md
git commit -m "test: verify Default.Empty compatibility"
```

## Self-Review

- **Spec coverage:**
  - `Default.Empty` 统一入口：Task 2
  - 仅支持 `String` / `Array` / `Dictionary` / `Set`：Task 2
  - 旧 `*Empty` API 改为 deprecated aliases，并新增 `SetEmpty`：Task 2
  - 默认值与解码行为验证：Task 3
  - 回归验证 `Default.Zero` 不受影响：Task 4

- **Placeholder scan:**
  - 计划中没有 `TODO` / `TBD` / “自行处理” 之类占位语句
  - 每个改码步骤都给出了明确代码块
  - 每个验证步骤都给出了明确命令与期望结果

- **Type consistency:**
  - `EmptyValue` / `EmptyProvider<T>` / `Default.Empty` / `Default.SetEmpty` 命名在所有任务中保持一致
  - `EmptyModel`、`SetContainerModel`、alias 测试命名在所有任务中保持一致
