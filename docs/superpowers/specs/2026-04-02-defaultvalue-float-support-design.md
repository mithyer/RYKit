# DefaultValue Float 支持设计

**日期：** 2026-04-02
**主题：** 为 `DefaultValue` 增加 `Float` 支持

---

## 背景

当前 `DefaultValue` 已支持 `Int`、`Double`、`Decimal`、`String`、`Bool` 及部分数组/字典类型的默认值与类型转换能力，但尚未对 `Float` 提供完整对外支持。这导致调用方无法直接声明：

```swift
@Default.FloatZero var value: Float
```

本次设计目标是在不大幅重构现有数值转换体系的前提下，为 `DefaultValue` 增加 `Float` 支持，并保持与现有 `Double` 使用体验尽量一致。

## 目标

1. 支持 `@Default.FloatZero var value: Float`
2. 支持 `Float` 在 `DefaultValue` 解码路径中的默认值回退
3. 支持常见类型向 `Float` 的转换，包括：
   - `String -> Float`
   - `Int -> Float`
   - `Double -> Float`
   - `Decimal -> Float`
   - `Bool -> Float`
4. 支持集合类型转换：
   - `[Float]`
   - `[String: Float]`
5. 保持现有失败兜底语义不变：缺失、`null`、无法转换时回落默认值

## 非目标

本次不做以下内容：

1. 不重构当前 `DefaultValue` 的整体类型转换架构
2. 不把内部浮点体系改造成 `Double + Float` 双原生通道
3. 不修改现有 `Int`、`Double`、`Decimal` 等已支持类型的行为语义
4. 不新增与本需求无关的 provider 或通用抽象层

## 推荐方案

采用 **方案 B：对外支持 Float，内部复用 Double 通道**。

### 核心思路

- 对外新增 `Float` 相关 API，使调用方可像使用 `Double` 一样使用 `Float`
- 内部仍延续当前实现中“浮点主要按 `Double` 处理”的思路
- 当目标类型为 `Float` 时，在现有可转换值基础上执行向下转换
- 不单独为 `SingleValue.raw` 增加新的 `Float` 主存储分支，尽量减少改动面

该方案满足用户对功能的需求，同时避免为 `Float` 引入一套完全平行但收益有限的底层实现。

## 详细设计

### 1. 对外 API

新增默认值 provider：

- `DefaultValueProviders.FloatZero`

新增类型别名：

- `Default.FloatZero`

目标用法：

```swift
private struct Model: Codable {
    @Default.FloatZero var score: Float
}
```

默认值为：

```swift
0.0
```

### 2. 类型转换设计

#### 单值转换

在当前 `convert(value:toType:)` 链路中加入 `Float.self` 目标类型判断。

可接受的输入来源包括：

- `Int`
- `Decimal`
- `Double`
- `String`
- `Bool`
- 已经是 `Float`

转换结果规则：

- `Int(3)` -> `Float(3)`
- `Decimal("1.25")` -> `Float(1.25)`
- `Double(3.14)` -> `Float(3.14)`
- `"2.5"` -> `Float(2.5)`
- `true` -> `1.0`
- `false` -> `0.0`

#### 集合转换

在 `tryMakeWrapperValue` 的数组与字典分支中新增：

- `[Float]`
- `[String: Float]`

行为与现有 `[Double]` / `[String: Double]` 保持一致，即逐项通过已有转换机制尝试转换，成功项进入结果集合。

### 3. 内部数据流

本次保持现有内部数值通道设计，不单独扩展新的 Float 原始载体体系。

数据流为：

1. 优先尝试直接 `decode(T.self)`
2. 若失败，则进入 `SingleValue` 或集合包装解码路径
3. 对于浮点值，继续优先复用现有 `Double` / `Decimal` 处理能力
4. 当最终目标类型是 `Float` 时，再将中间值转换为 `Float`

这意味着：

- `Float` 对外是受支持类型
- `Float` 在内部不是独立主通道，而是建立在现有浮点解码能力之上

这是本方案刻意选择的实现边界，用于降低改动复杂度。

### 4. 失败与默认值策略

保留现有 `DefaultValue` 失败回退语义：

- key 缺失 -> 默认值
- 值为 `null` -> 默认值
- 值存在但无法转换 -> 默认值

对于 `Float`，默认值为 `0`。

不会因为本次新增 `Float` 支持而改变 `DefaultValue` 现有异常与回退行为。

## 兼容性与风险

### 兼容性

该改动为向后兼容增强：

- 不改变现有 `DefaultValue` 公共接口语义
- 不影响已存在的 `Int` / `Double` / `Decimal` / `String` / `Bool` 路径
- 仅新增 `Float` 能力

### 风险

1. **精度语义风险**
   - 由于内部以 `Double` 浮点通道为主，`Float` 的解码本质上是“先按现有浮点能力解析，再向下转为 `Float`”
   - 这可能带来与 `Float` 原生直接解析一致但精度更受限的结果
   - 对当前业务场景可接受，且与用户预期一致

2. **类型分支遗漏风险**
   - 当前实现依赖多个 `if T.self == ...` 分支
   - 若只补单值而遗漏数组/字典路径，会导致支持不完整
   - 需通过测试覆盖确保行为一致

## 测试策略

新增或补充测试覆盖以下场景：

1. `FloatZero` 默认值测试
2. `@Default.FloatZero` 直接解码 `Float`
3. 缺失 key 时回退 `0`
4. `null` 时回退 `0`
5. `String -> Float`
6. `Int -> Float`
7. `Double -> Float`
8. `Decimal -> Float`
9. `Bool -> Float`
10. `[Float]` 转换
11. `[String: Float]` 转换

测试应放在现有 `ValueWrapperTests.swift` 中，保持与当前测试组织方式一致。

## 涉及文件

预计涉及：

- `Classes/Core/Codable/ValueWrapper/DefaultValue.swift`
- `Project/RYKitTests/ValueWrapperTests.swift`

不新增新的模块级文件，优先在现有实现与测试文件中补齐支持。

## 结论

本设计采用“**对外支持 Float，内部复用 Double 通道**”的方式，为 `DefaultValue` 提供 `Float` 默认值与转换能力。

该方案具备以下特点：

- 满足调用方新增 `Float` 使用需求
- 与现有 `Double` 的使用体验尽量一致
- 控制改动范围，不引入不必要重构
- 保持向后兼容和现有失败回退语义稳定

该设计适合直接进入实现计划阶段。
