# Default.Zero 自动数值零值设计

**日期：** 2026-04-02
**主题：** 为 `DefaultValue` 增加 `Default.Zero` 自动数值零值入口

---

## 背景

当前 `DefaultValue` 已分别提供以下数值零值入口：

- `@Default.IntZero`
- `@Default.FloatZero`
- `@Default.DoubleZero`
- `@Default.DecimalZero`

这类 API 虽然清晰，但在使用层面需要调用方手动区分具体数值类型。用户希望将它们收敛为统一写法：

```swift
@Default.Zero var intValue: Int
@Default.Zero var floatValue: Float
@Default.Zero var doubleValue: Double
@Default.Zero var decimalValue: Decimal
```

即由 `Default.Zero` 根据属性声明类型自动识别应使用的零值，而不再要求调用方显式选择 `IntZero`、`FloatZero` 等 provider。

当前仓库中 `DefaultValue` 的数值转换链路已经支持 `Int`、`Double`、`Float`、`Decimal` 的单值转换，且 `Float` 能力已经补齐，因此本次需求重点不在解码转换重构，而在于统一默认值 provider 的暴露方式。

## 目标

1. 支持统一写法：

```swift
@Default.Zero var intValue: Int
@Default.Zero var floatValue: Float
@Default.Zero var doubleValue: Double
@Default.Zero var decimalValue: Decimal
```

2. `Default.Zero` 仅用于数值类型零值，不承担字符串空串、布尔 false、数组空、字典空等语义。
3. 保持现有 `DefaultValue` 解码与类型转换行为不变。
4. 保持现有 API 向后兼容：
   - `Default.IntZero`
   - `Default.FloatZero`
   - `Default.DoubleZero`
   - `Default.DecimalZero`
5. 将“零值能力”沉淀为统一的类型约束，而不是继续为每个数值类型手写一份独立 provider。

## 非目标

本次不做以下内容：

1. 不把 `Default.Zero` 扩展到 `Bool`、`String`、数组、字典等非“数值零”类型。
2. 不重写 `DefaultValue` 的解码路径。
3. 不删除现有 `Default.IntZero` / `Default.FloatZero` / `Default.DoubleZero` / `Default.DecimalZero` 对外入口；它们会保留为迁移期兼容别名。
4. 不新增与本需求无关的默认值抽象体系，例如“任意 Empty 值”或“任意 Init 值”的统一入口。

## 推荐方案

采用**方案 A：引入数值零协议 + 泛型零值 provider，并对外暴露统一 `Default.Zero` 入口**。

### 核心思路

新增一个专门表示“数值零值”的协议：

```swift
public protocol ZeroValue {
    static var zeroValue: Self { get }
}
```

通过条件扩展为所有 `Numeric` 类型提供默认零值实现：

```swift
public extension ZeroValue where Self: Numeric {
    static var zeroValue: Self { .zero }
}
```

然后显式声明以下类型遵守该协议：

- `Int`
- `Float`
- `Double`
- `Decimal`

再新增泛型 provider：

```swift
public enum ZeroProvider<T: Codable & ZeroValue>: DefaultValueProvider {
    public static var `default`: T { T.zeroValue }
}
```

最后在 `Default` 命名空间下暴露统一入口 `Default.Zero`，并将旧的 `Default.IntZero` / `Default.FloatZero` / `Default.DoubleZero` / `Default.DecimalZero` 改为指向新入口的 deprecated typealias。

该方案的优势是：

- 对外 API 最简洁，符合用户直觉
- 零值语义集中在协议层，扩展性好
- 用 `Numeric` 默认实现减少重复代码，同时仍通过显式遵守限制当前支持范围
- 旧 API 继续可用，但通过 deprecation 明确迁移方向
- 底层仍复用现有 `DefaultValue` 包装器，不需要重构解码体系

## 详细设计

### 1. 对外 API

目标新增统一入口：

```swift
public struct Default {
    public typealias Zero<T: Codable & ZeroValue> = DefaultValue<ZeroProvider<T>>
}
```

调用方式目标为：

```swift
private struct Model: Codable {
    @Default.Zero var intValue: Int
    @Default.Zero var floatValue: Float
    @Default.Zero var doubleValue: Double
    @Default.Zero var decimalValue: Decimal
}
```

其默认值语义为：

- `Int -> 0`
- `Float -> 0`
- `Double -> 0`
- `Decimal -> .zero`

现有 API 保持可用，但迁移策略调整为 deprecated compatibility aliases：

- `Default.IntZero`
- `Default.FloatZero`
- `Default.DoubleZero`
- `Default.DecimalZero`

这些旧入口会直接 typealias 到新的 `Default.Zero`，从而：

- 不破坏现有调用方
- 不再维护重复的按类型 zero provider 实现
- 通过编译期 deprecation message 引导迁移到 `@Default.Zero`

### 2. 内部类型设计

#### 2.1 新增 `ZeroValue` 协议

建议新增专用协议：

```swift
public protocol ZeroValue {
    static var zeroValue: Self { get }
}
```

不复用当前 `Initializable`，原因如下：

- `init()` 的语义是“可初始化”，不是“数值零”
- 本需求聚焦于数值类型统一零值，不应把“零值”和“默认构造值”混为一谈
- 新协议的约束更精确，编译期语义更清晰

#### 2.2 为数值类型声明 `ZeroValue` 遵守关系

在现有基础类型扩展区域补充显式遵守声明：

- `extension Int: ZeroValue {}`
- `extension Float: ZeroValue {}`
- `extension Double: ZeroValue {}`
- `extension Decimal: ZeroValue {}`

具体零值实现不再由每个类型单独书写，而是统一复用：

```swift
public extension ZeroValue where Self: Numeric {
    static var zeroValue: Self { .zero }
}
```

这样既减少重复代码，又保持当前支持范围明确，只开放给显式声明遵守 `ZeroValue` 的数值类型。

#### 2.3 新增泛型 `ZeroProvider<T>`

新增统一 provider：

```swift
public enum ZeroProvider<T: Codable & ZeroValue>: DefaultValueProvider {
    public static var `default`: T { T.zeroValue }
}
```

这样可以将原来按类型拆分的：

- `IntZero`
- `FloatZero`
- `DoubleZero`
- `DecimalZero`

统一为一种通用 provider 实现，而不影响原有 `DefaultValue<Provider>` 架构。

#### 2.4 与现有解码逻辑的关系

本次不修改以下核心逻辑：

- `convert(value:toType:)`
- `tryMakeWrapperValue(container:rawValue:)`

原因是当前这些逻辑已经按照目标类型 `T.self` 进行解码和跨类型转换，足以支撑 `Int` / `Float` / `Double` / `Decimal` 的行为。

因此：

- `Default.Zero` 负责统一“默认值 provider”入口
- 解码和转换仍由现有机制负责

这意味着本次改动是 API 与 provider 抽象层的增强，而不是对解码管线的重构。

### 3. 可行性与风险

#### 3.1 最大风险：Swift 语法自动推断能力

方案 A 成立的前提是 Swift 编译器允许如下写法自动推断 wrapper 泛型：

```swift
@Default.Zero var count: Int
```

即由属性类型 `Int` 自动推断出：

```swift
DefaultValue<ZeroProvider<Int>>
```

这是本方案唯一的高风险点。

#### 3.2 风险表现

若当前项目所使用的 Swift 版本对 property wrapper + 嵌套泛型 typealias 的推断能力不足，则可能出现：

- `Generic parameter could not be inferred`
- property wrapper 无法从属性类型反推泛型参数

若发生这种情况，说明该设计在“完全自动识别类型”的语法层面不可落地。

#### 3.3 风险边界

除语法推断外，其它风险都较低：

- 不改变现有解码主链路
- 不移除现有 API
- 不影响旧测试
- `ZeroValue` 为新增协议，影响面可控

因此本次设计的成败关键并不在运行时逻辑，而在于目标语法能否编译通过。

### 4. 错误与兼容性策略

#### 编译期约束

`Default.Zero` 只允许用于实现了 `ZeroValue` 的类型。如果使用者写出：

```swift
@Default.Zero var name: String
```

则应在编译期失败，而不是运行时兜底。这是预期行为，因为：

- `String` 不是数值零值类型
- `Zero` 的语义应保持严格

#### 向后兼容

对外仍保留以下入口：

- `Default.IntZero`
- `Default.FloatZero`
- `Default.DoubleZero`
- `Default.DecimalZero`

但实现方式改为：

- 旧入口全部声明为 `@available(*, deprecated, message: "Use @Default.Zero instead.")`
- 旧入口直接 typealias 到新的 `Default.Zero`
- 删除旧的按类型 zero providers，避免底层重复实现

这样：

- 旧代码无需立即修改
- 新代码可直接使用 `@Default.Zero`
- 编译期 warning 会给出明确迁移指引
- 底层只有一套零值 provider 逻辑

## 测试策略

### 1. 语法可行性测试

新增一个最小模型，验证以下写法能否编译：

```swift
private struct ZeroModel: Codable {
    @Default.Zero var intValue: Int
    @Default.Zero var floatValue: Float
    @Default.Zero var doubleValue: Double
    @Default.Zero var decimalValue: Decimal
}
```

这是本需求的第一验收门槛。

### 2. 行为测试

若语法可行，补充以下测试：

1. 默认值测试
   - `Int -> 0`
   - `Float -> 0`
   - `Double -> 0`
   - `Decimal -> .zero`

2. 缺失 key 回退
   - `{}` 解码后所有属性为零值

3. `null` 回退
   - `null` 解码后所有属性为零值

4. 同类型直接解码
   - 数值直接解码成功

5. 现有跨类型转换沿用
   - 字符串数值转 `Int` / `Float` / `Double` / `Decimal`
   - 整数转浮点
   - 浮点转整数（若当前语义允许截断则保持一致）

6. 兼容性测试
   - 现有 `IntZero` / `FloatZero` / `DoubleZero` / `DecimalZero` 测试继续通过

### 3. 测试文件位置

测试应继续放在：

- `Project/RYKitTests/ValueWrapperTests.swift`

与现有 `DefaultValue` 测试组织保持一致。

## 涉及文件

预计涉及以下文件：

- `Classes/Core/Codable/ValueWrapper/DefaultValue.swift`
- `Project/RYKitTests/ValueWrapperTests.swift`

设计文档新增为：

- `docs/superpowers/specs/2026-04-02-default-zero-design.md`

## 验收标准

本次设计成功的标准是：

1. 可以直接写：

```swift
@Default.Zero var count: Int
@Default.Zero var price: Float
@Default.Zero var ratio: Double
@Default.Zero var amount: Decimal
```

2. 缺失 key / `null` 时，均自动回退到对应零值
3. 现有数值转换能力保持不变
4. 旧 API 继续可用，不引入破坏性改动
5. 所有新增与既有相关测试通过

## 结论

本设计通过新增 `ZeroValue` 协议和泛型 `ZeroProvider<T>`，为 `DefaultValue` 提供统一的 `Default.Zero` 数值零值入口。

该设计具备以下特点：

- 对外 API 更统一、更简洁
- 语义严格限定为“数值零值”
- 底层复用现有 `DefaultValue` 解码体系
- 与已有 `IntZero` / `FloatZero` / `DoubleZero` / `DecimalZero` 保持兼容

唯一需要重点验证的是：当前 Swift 编译器是否支持 `@Default.Zero var value: T` 的属性包装器泛型自动推断。若这一点成立，则该设计可以直接进入实现阶段。
