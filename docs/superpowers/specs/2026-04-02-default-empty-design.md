# Default.Empty 统一空值设计

**日期：** 2026-04-02
**主题：** 为 `DefaultValue` 增加 `Default.Empty` 统一空值入口

---

## 背景

当前 `DefaultValue` 已分别提供以下空值入口：

- `@Default.StringEmpty`
- `@Default.ArrayEmpty`
- `@Default.DicEmpty`

这些 API 各自清晰，但在使用层面需要调用方手动判断具体容器类型并选择不同入口。继 `Default.Zero` 统一数值零值入口之后，用户希望继续把“空值”相关默认值 API 收敛为统一写法：

```swift
@Default.Empty var name: String
@Default.Empty var tags: [String]
@Default.Empty var mapping: [String: Int]
@Default.Empty var ids: Set<Int>
```

即由 `Default.Empty` 根据属性声明类型自动识别应使用的空值，而不再要求调用方显式选择 `StringEmpty`、`ArrayEmpty`、`DicEmpty` 等 provider。用户同时要求：

- `String` 正式纳入 `Empty` 语义范围，而不是仅作兼容处理
- `Set` 一并纳入支持范围
- 旧入口全部保留为 deprecated compatibility aliases
- 补充 `Default.SetEmpty`，但同样标记为 deprecated

本次需求重点仍然是统一默认值 provider 的暴露方式，而不是重写 `DefaultValue` 的解码与转换主链路。

## 目标

1. 支持统一写法：

```swift
@Default.Empty var name: String
@Default.Empty var tags: [String]
@Default.Empty var mapping: [String: Int]
@Default.Empty var ids: Set<Int>
```

2. `Default.Empty` 仅承担“明确空值”的语义，当前支持范围为：
   - `String`
   - `Array`
   - `Dictionary`
   - `Set`
3. 保持现有 `DefaultValue` 解码与类型转换行为不变。
4. 保持现有 API 向后兼容，并统一迁移到 `Default.Empty`：
   - `Default.StringEmpty`
   - `Default.ArrayEmpty`
   - `Default.DicEmpty`
   - `Default.SetEmpty`
5. 删除旧的按类型 Empty providers，避免底层出现两套空值实现。

## 非目标

本次不做以下内容：

1. 不把 `Default.Empty` 扩展到 `Int`、`Bool`、自定义结构体等非明确空值类型。
2. 不将 `Empty` 泛化为“凡是 `init()` 都能用”的统一入口。
3. 不重写 `DefaultValue` 的解码路径。
4. 不把 `CaseFirst`、`BoolFalse`、`Init` 等其它默认值语义并入 `Empty`。

## 推荐方案

采用**方案 A：引入 `EmptyValue` 协议 + 泛型 `EmptyProvider<T>`，并对外暴露统一 `Default.Empty` 入口**。

### 核心思路

新增一个专门表示“明确空值”的协议：

```swift
public protocol EmptyValue {
    static var emptyValue: Self { get }
}
```

对于支持类型，采用“条件默认实现 + 显式遵守”的组合策略：

1. 对 `RangeReplaceableCollection` 提供统一默认实现：

```swift
public extension EmptyValue where Self: RangeReplaceableCollection {
    static var emptyValue: Self { Self() }
}
```

这会自然覆盖：
- `String`
- `Array`
- `Set`

2. `Dictionary` 不走这一条约束，因此单独声明遵守并提供 `[:]` 语义。

然后新增泛型 provider：

```swift
public enum EmptyProvider<T: Codable & EmptyValue>: DefaultValueProvider {
    public static var `default`: T { T.emptyValue }
}
```

最后在 `Default` 命名空间下暴露统一入口 `Default.Empty`，并将旧的 `Default.StringEmpty` / `Default.ArrayEmpty` / `Default.DicEmpty` / `Default.SetEmpty` 改为指向新入口的 deprecated typealias。

该方案的优势是：

- 对外 API 简洁且统一
- `Empty` 的语义边界清晰，不会退化成泛化版 `Init`
- `String`、`Array`、`Set` 可以共享一套基于 `RangeReplaceableCollection` 的默认实现，减少重复代码
- `Dictionary` 保持单独明确处理，避免混淆约束来源
- 旧 API 继续可用，但通过 deprecation 明确迁移方向
- 底层仍复用现有 `DefaultValue` 包装器，不需要重构解码体系

## 详细设计

### 1. 对外 API

目标新增统一入口：

```swift
public struct Default {
    public typealias Empty<T: Codable & EmptyValue> = DefaultValue<EmptyProvider<T>>
}
```

调用方式目标为：

```swift
private struct Model: Codable {
    @Default.Empty var name: String
    @Default.Empty var tags: [String]
    @Default.Empty var mapping: [String: Int]
    @Default.Empty var ids: Set<Int>
}
```

其默认值语义为：

- `String -> ""`
- `Array -> []`
- `Dictionary -> [:]`
- `Set -> []`

现有 API 保持可用，但迁移策略调整为 deprecated compatibility aliases：

- `Default.StringEmpty`
- `Default.ArrayEmpty`
- `Default.DicEmpty`
- `Default.SetEmpty`

这些旧入口会直接 typealias 到新的 `Default.Empty`，从而：

- 不破坏现有调用方
- 不再维护重复的按类型 empty provider 实现
- 通过编译期 deprecation message 引导迁移到 `@Default.Empty`

### 2. 内部类型设计

#### 2.1 新增 `EmptyValue` 协议

建议新增专用协议：

```swift
public protocol EmptyValue {
    static var emptyValue: Self { get }
}
```

不复用当前 `Initializable`，原因如下：

- `init()` 的语义是“可初始化”，不是“明确空值”
- 本需求聚焦于字符串与集合类的空值统一，不应把“空值”和“默认构造值”混为一谈
- 新协议的约束更精确，编译期语义更清晰

#### 2.2 为字符串与集合类型声明 `EmptyValue` 遵守关系

在现有基础类型扩展区域补充显式遵守声明：

- `extension String: EmptyValue {}`
- `extension Array: EmptyValue {}`
- `extension Set: EmptyValue {}`
- `extension Dictionary: EmptyValue {}`

其中：

- `String`、`Array`、`Set` 通过 `RangeReplaceableCollection` 条件扩展获得默认实现
- `Dictionary` 单独提供 `emptyValue` 实现，返回 `[:]`

这样既减少重复代码，又保持当前支持范围明确，只开放给显式声明遵守 `EmptyValue` 的类型。

#### 2.3 新增泛型 `EmptyProvider<T>`

新增统一 provider：

```swift
public enum EmptyProvider<T: Codable & EmptyValue>: DefaultValueProvider {
    public static var `default`: T { T.emptyValue }
}
```

这样可以将原来按类型拆分的：

- `StringEmpty`
- `ArrayEmpty`
- `DicEmpty`
- `SetEmpty`

统一为一种通用 provider 实现，而不影响原有 `DefaultValue<Provider>` 架构。

#### 2.4 与现有解码逻辑的关系

本次不修改以下核心逻辑：

- `convert(value:toType:)`
- `tryMakeWrapperValue(container:rawValue:)`

原因是当前 `String`、`Array`、`Dictionary` 的解码路径已存在，`Set` 也可以走 `Codable` 的现有解码行为。`Default.Empty` 只负责在缺失值或 `null` 情况下提供统一的空默认值。

因此：

- `Default.Empty` 负责统一“默认值 provider”入口
- 解码和转换仍由现有机制负责

这意味着本次改动是 API 与 provider 抽象层的增强，而不是对解码管线的重构。

### 3. 可行性与风险

#### 3.1 最大风险：Swift 语法自动推断能力

方案成立的前提是 Swift 编译器允许如下写法自动推断 wrapper 泛型：

```swift
@Default.Empty var tags: [String]
@Default.Empty var mapping: [String: Int]
@Default.Empty var ids: Set<Int>
```

即由属性类型自动推断出：

```swift
DefaultValue<EmptyProvider<[String]>>
DefaultValue<EmptyProvider<[String: Int]>>
DefaultValue<EmptyProvider<Set<Int>>>
```

这与 `Default.Zero` 属于同一类语法风险，应先用最小模型验证。

#### 3.2 风险表现

若当前项目所使用的 Swift 版本对 property wrapper + 嵌套泛型 typealias 的推断能力不足，则可能出现：

- `Generic parameter could not be inferred`
- property wrapper 无法从属性类型反推泛型参数

若发生这种情况，说明该设计在“完全自动识别类型”的语法层面不可落地。

#### 3.3 风险边界

除语法推断外，其它风险都较低：

- 不改变现有解码主链路
- 不移除现有 API
- 不影响旧调用方
- `EmptyValue` 为新增协议，影响面可控

### 4. 错误与兼容性策略

#### 编译期约束

`Default.Empty` 只允许用于实现了 `EmptyValue` 的类型。如果使用者写出：

```swift
@Default.Empty var count: Int
```

则应在编译期失败，而不是运行时兜底。这是预期行为，因为：

- `Int` 不是当前设计中的明确空值类型
- `Empty` 的语义应保持严格

#### 向后兼容

对外仍保留以下入口：

- `Default.StringEmpty`
- `Default.ArrayEmpty`
- `Default.DicEmpty`
- `Default.SetEmpty`

但实现方式改为：

- 旧入口全部声明为 `@available(*, deprecated, message: "Use @Default.Empty instead.")`
- 旧入口直接 typealias 到新的 `Default.Empty`
- 删除旧的按类型 empty providers，避免底层重复实现

这样：

- 旧代码无需立即修改
- 新代码可直接使用 `@Default.Empty`
- 编译期 warning 会给出明确迁移指引
- 底层只有一套空值 provider 逻辑

## 测试策略

### 1. 语法可行性测试

新增一个最小模型，验证以下写法能否编译：

```swift
private struct EmptyModel: Codable {
    @Default.Empty var name: String
    @Default.Empty var tags: [String]
    @Default.Empty var mapping: [String: Int]
    @Default.Empty var ids: Set<Int>
}
```

这是本需求的第一验收门槛。

### 2. 行为测试

若语法可行，补充以下测试：

1. 默认值测试
   - `String -> ""`
   - `Array -> []`
   - `Dictionary -> [:]`
   - `Set -> []`

2. 缺失 key 回退
   - `{}` 解码后所有属性为空值

3. `null` 回退
   - `null` 解码后所有属性为空值

4. 同类型直接解码
   - `String` / `Array` / `Dictionary` / `Set` 直接解码成功

5. 兼容别名测试
   - `Default.StringEmpty`
   - `Default.ArrayEmpty`
   - `Default.DicEmpty`
   - `Default.SetEmpty`

### 3. 回归测试

至少运行 `DefaultValueTests`，确认：

- 现有字符串默认值测试不回归
- 现有数组默认值测试不回归
- 现有字典默认值测试不回归
- 新增的 `Set` 默认值测试通过
- 现有 `Default.Zero` 测试不受影响

## 结论

推荐采用 `EmptyValue + EmptyProvider<T> + Default.Empty` 的方式统一字符串与集合类空值入口，当前范围限定为 `String`、`Array`、`Dictionary`、`Set`。旧 `StringEmpty` / `ArrayEmpty` / `DicEmpty` / `SetEmpty` 全部保留为 deprecated compatibility aliases，从而在不破坏现有调用方的前提下，把 API 收敛到统一的 `@Default.Empty` 写法。