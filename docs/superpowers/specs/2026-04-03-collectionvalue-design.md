# CollectionValue 设计说明

日期：2026-04-03  
范围：`Classes/Core/Codable/ValueWrapper/CollectionValue.swift`

## 背景

当前 `CollectionValue.swift` 仅有基础类型定义与 TODO。项目已存在 `CodableDictionary` / `CodableArray`（位于 `Classes/Core/Codable/Codable+Any.swift`），可用于 `[String: Any]` 与 `[Any]` 的编码解码桥接。

目标是在不改变现有调用方式的前提下，完成 `@CollectionValue` 剩余逻辑，并对失败场景采用“容错返回 nil”。

## 目标

1. 保持 `CollectionValue<T>` 单一泛型包装器形态，不拆分 API。
2. 支持两类 `T`：
   - `[Any]`
   - `[String: Any]`
3. 解码失败不抛错，统一置为 `nil`。
4. 编码时 `wrappedValue == nil` 不输出字段（由 keyed container 编码扩展配合实现）。

## 非目标

1. 不新增字符串 JSON（如 `"{...}"` / `"[...]"`）到集合的二次解析。
2. 不新增额外 provider / alias 体系。
3. 不扩展到其它 `AnyCollectionValue` 实现类型。

## 方案对比

1. 推荐方案：保留 `CollectionValue<T>`，内部按 `T` 分支到 `CodableArray` / `CodableDictionary`。
   - 优点：改动最小，兼容现有调用，落地快。
   - 缺点：需要运行时类型判断。
2. 备选方案：拆分成 `ArrayValue` 与 `DictionaryValue`。
   - 优点：分支清晰。
   - 缺点：需要变更 API，超出本次范围。
3. 备选方案：内部引入 `Storage enum` 再桥接到 `T`。
   - 优点：内部语义统一。
   - 缺点：复杂度偏高，对当前需求过度设计。

## 架构与组件

### 1) `CollectionValue<T: AnyCollectionValue>`

对外提供：
- `wrappedValue: T?`
- `init()`
- `init(wrappedValue: T?)`
- `init(from:)`
- `encode(to:)`
- `description`

### 2) 容器扩展

- `KeyedDecodingContainer.decode(CollectionValue<T>.Type, forKey:)`
  - `decodeIfPresent` 成功返回解析结果
  - 缺失 key 或解析失败返回 `CollectionValue()`（`wrappedValue == nil`）
- `KeyedEncodingContainer.encode(CollectionValue<T>, forKey:)`
  - 仅在 `wrappedValue != nil` 时编码
  - 编码值直接透传给已有 `[Any]?` / `[String: Any]?` 编码扩展

## 数据流

### 解码流

1. 从 `singleValueContainer` 开始。
2. 如果是 `null`，直接 `wrappedValue = nil`。
3. 如果 `T == [Any]`，尝试 `CodableArray`。
4. 如果 `T == [String: Any]`，尝试 `CodableDictionary`。
5. 以上失败则 `wrappedValue = nil`，不抛错。

### 编码流

1. `wrappedValue == nil` 时不输出字段（keyed encode 扩展不执行 `encode`）。
2. `T == [Any]` 时包为 `CodableArray` 编码。
3. `T == [String: Any]` 时包为 `CodableDictionary` 编码。
4. 兜底分支不编码，避免引发不必要异常。

## 错误处理策略

采用弱容错语义（与 `PreferValue` 一致）：

1. 类型不匹配（例如 JSON 是字符串、数字）不抛错，值置 `nil`。
2. 不支持的 `T`（理论上不应发生）不抛错，值置 `nil` 或跳过编码。
3. `null` 视为有效空值，置 `nil`。

## 测试设计

在 `Project/RYKitTests/ValueWrapperTests.swift` 新增 `CollectionValue` 相关模型与测试组，覆盖：

1. 解码数组成功：`[Any]`
2. 解码字典成功：`[String: Any]`
3. 缺失 key 解码为 `nil`
4. `null` 解码为 `nil`
5. 类型不匹配解码为 `nil`
6. 非空编码输出字段
7. `nil` 编码不输出字段

## 修改清单

1. `Classes/Core/Codable/ValueWrapper/CollectionValue.swift`
2. `Project/RYKitTests/ValueWrapperTests.swift`

---

以上设计已按确认的约束固定：
- 解码失败置 `nil`
- `nil` 编码时省略 key
- 采用单一泛型包装器方案
