# DefaultValue Float Support Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add `Float` support to `DefaultValue` so callers can declare `@Default.FloatZero var value: Float` while keeping the internal floating-point conversion pipeline centered on `Double`.

**Architecture:** Extend the existing `DefaultValue` conversion branches in `DefaultValue.swift` rather than refactoring the type system. Expose a new `FloatZero` provider and `Default.FloatZero` alias, teach `convert(value:toType:)` and `tryMakeWrapperValue(...)` to recognize `Float`, and cover the new paths with focused XCTest cases in `ValueWrapperTests.swift`.

**Tech Stack:** Swift, Foundation, XCTest, Swift Package Manager

---

## File Structure

- Modify: `Classes/Core/Codable/ValueWrapper/DefaultValue.swift`
  - Add `Float` to `Initializable`
  - Add `FloatZero` provider and `Default.FloatZero` typealias
  - Extend `SingleValueConvertable` with `convertToFloat()`
  - Implement `Float` conversions while keeping `Double` as the primary floating-point raw path
  - Add `Float` branches in `convert(value:toType:)` and `tryMakeWrapperValue(...)`
- Modify: `Project/RYKitTests/ValueWrapperTests.swift`
  - Add Float-backed test models
  - Add failing/passing tests for default values, single-value conversion, array conversion, and dictionary conversion

---

### Task 1: Add failing tests for Float default value and single-value decoding

**Files:**
- Modify: `Project/RYKitTests/ValueWrapperTests.swift:12-192`
- Test: `Project/RYKitTests/ValueWrapperTests.swift`

- [ ] **Step 1: Write the failing test models and Float tests**

```swift
private struct DefaultValueModel: Codable {
    @Default.IntZero var intValue: Int
    @Default.BoolFalse var boolValue: Bool
    @Default.StringEmpty var stringValue: String
    @Default.DoubleZero var doubleValue: Double
    @Default.DecimalZero var decimalValue: Decimal
    @Default.FloatZero var floatValue: Float
}

private struct DefaultValueFloatCollectionModel: Codable {
    @Default.ArrayEmpty<[Float]> var floatArray: [Float]
    @Default.DicEmpty<String, Float> var floatDictionary: [String: Float]
}
```

Add these test methods inside `final class DefaultValueTests: XCTestCase`:

```swift
func test_decode_float_withMatchingType_succeeds() throws {
    let json = """
    {"intValue": 42, "boolValue": true, "stringValue": "hello", "doubleValue": 3.14, "decimalValue": 99.99, "floatValue": 1.25}
    """
    let model = try decode(DefaultValueModel.self, from: json)

    XCTAssertEqual(model.floatValue, 1.25, accuracy: 0.0001)
}

func test_decode_float_withMissingKey_usesDefault() throws {
    let json = "{}"
    let model = try decode(DefaultValueModel.self, from: json)

    XCTAssertEqual(model.floatValue, 0, accuracy: 0.0001)
}

func test_decode_float_withNullValue_usesDefault() throws {
    let json = """
    {"intValue": null, "boolValue": null, "stringValue": null, "doubleValue": null, "decimalValue": null, "floatValue": null}
    """
    let model = try decode(DefaultValueModel.self, from: json)

    XCTAssertEqual(model.floatValue, 0, accuracy: 0.0001)
}

func test_decode_stringToFloat_converts() throws {
    let json = """
    {"intValue": 0, "boolValue": false, "stringValue": "", "doubleValue": 0, "decimalValue": 0, "floatValue": "12.5"}
    """
    let model = try decode(DefaultValueModel.self, from: json)

    XCTAssertEqual(model.floatValue, 12.5, accuracy: 0.0001)
}

func test_decode_intToFloat_converts() throws {
    let json = """
    {"intValue": 0, "boolValue": false, "stringValue": "", "doubleValue": 0, "decimalValue": 0, "floatValue": 7}
    """
    let model = try decode(DefaultValueModel.self, from: json)

    XCTAssertEqual(model.floatValue, 7, accuracy: 0.0001)
}

func test_decode_boolToFloat_converts() throws {
    let json = """
    {"intValue": 0, "boolValue": false, "stringValue": "", "doubleValue": 0, "decimalValue": 0, "floatValue": true}
    """
    let model = try decode(DefaultValueModel.self, from: json)

    XCTAssertEqual(model.floatValue, 1, accuracy: 0.0001)
}

func test_providers_floatZero_default() {
    XCTAssertEqual(DefaultValueProviders.FloatZero.default, 0, accuracy: 0.0001)
}
```

- [ ] **Step 2: Run the focused tests to verify they fail**

Run:
```bash
swift test --filter DefaultValueTests
```

Expected: FAIL with compile errors such as `type 'Default' has no member 'FloatZero'` and `type 'DefaultValueProviders' has no member 'FloatZero'`.

- [ ] **Step 3: Commit the failing tests**

```bash
git add Project/RYKitTests/ValueWrapperTests.swift
git commit -m "test: add failing DefaultValue float tests"
```

### Task 2: Implement Float provider and scalar conversion support

**Files:**
- Modify: `Classes/Core/Codable/ValueWrapper/DefaultValue.swift:57-258`
- Test: `Project/RYKitTests/ValueWrapperTests.swift`

- [ ] **Step 1: Extend the conversion protocols and providers in `DefaultValue.swift`**

Update these declarations:

```swift
func convert<T: SingleValueConvertable>(value: Any, toType: T.Type) -> T? {
    if value is T {
        return value as? T
    }
    guard let value = value as? any SingleValueConvertable else {
        return nil
    }
    if toType == Int.self {
        return value.convertToInt() as? T
    }
    if toType == Decimal.self {
        return value.convertToDecimal() as? T
    }
    if toType == Double.self {
        return value.convertToDouble() as? T
    }
    if toType == Float.self {
        return value.convertToFloat() as? T
    }
    if toType == String.self {
        return value.convertToString() as? T
    }
    if toType == Bool.self {
        return value.convertToBool() as? T
    }
    return nil
}
```

```swift
extension Float: Initializable {}
```

```swift
public enum FloatZero: DefaultValueProvider {
    public static let `default`: Float = 0
}
```

```swift
public typealias FloatZero = DefaultValue<DefaultValueProviders.FloatZero>
```

```swift
public protocol SingleValueConvertable {
    func convertToInt() -> Int?
    func convertToDecimal() -> Decimal?
    func convertToString() -> String?
    func convertToDouble() -> Double?
    func convertToFloat() -> Float?
    func convertToBool() -> Bool?
}
```

- [ ] **Step 2: Implement `convertToFloat()` on existing conforming types**

Add or update these conformances:

```swift
extension Int: SingleValueConvertable {
    public func convertToInt() -> Int? {
        self
    }

    public func convertToDecimal() -> Decimal? {
        Decimal(self)
    }

    public func convertToString() -> String? {
        "\(self)"
    }

    public func convertToDouble() -> Double? {
        Double(self)
    }

    public func convertToFloat() -> Float? {
        Float(self)
    }

    public func convertToBool() -> Bool? {
        self == 0 ? false : (self == 1 ? true : nil)
    }
}
```

```swift
extension Decimal: SingleValueConvertable {
    public func convertToInt() -> Int? {
        guard isNormal else {
            return nil
        }
        return Int((self as NSDecimalNumber).doubleValue)
    }

    public func convertToDecimal() -> Decimal? {
        self
    }

    public func convertToString() -> String? {
        "\(self)"
    }

    public func convertToDouble() -> Double? {
        (self as NSDecimalNumber).doubleValue
    }

    public func convertToFloat() -> Float? {
        Float((self as NSDecimalNumber).doubleValue)
    }

    public func convertToBool() -> Bool? {
        self == 0 ? false : (self == 1 ? true : nil)
    }
}
```

```swift
extension String: SingleValueConvertable {
    public func convertToInt() -> Int? {
        Int(self)
    }

    public func convertToDecimal() -> Decimal? {
        Decimal(string: self)
    }

    public func convertToString() -> String? {
        self
    }

    public func convertToDouble() -> Double? {
        Double(self)
    }

    public func convertToFloat() -> Float? {
        Double(self).map(Float.init)
    }

    public func convertToBool() -> Bool? {
        ["true", "y", "t", "yes", "1"].contains { caseInsensitiveCompare($0) == .orderedSame }
    }
}
```

```swift
extension Double: SingleValueConvertable {
    public func convertToInt() -> Int? {
        Int(self)
    }

    public func convertToDecimal() -> Decimal? {
        Decimal(self)
    }

    public func convertToString() -> String? {
        "\(self)"
    }

    public func convertToDouble() -> Double? {
        self
    }

    public func convertToFloat() -> Float? {
        Float(self)
    }

    public func convertToBool() -> Bool? {
        self == 1 ? true : (self == 0 ? false : nil)
    }
}
```

```swift
extension Bool: SingleValueConvertable {
    public func convertToInt() -> Int? {
        self ? 1 : 0
    }

    public func convertToDecimal() -> Decimal? {
        Decimal(self ? 1 : 0)
    }

    public func convertToString() -> String? {
        "\(self)"
    }

    public func convertToDouble() -> Double? {
        self ? 1.0 : 0.0
    }

    public func convertToFloat() -> Float? {
        self ? 1.0 : 0.0
    }

    public func convertToBool() -> Bool? {
        self
    }
}
```

Add a new conformance:

```swift
extension Float: SingleValueConvertable {
    public func convertToInt() -> Int? {
        Int(self)
    }

    public func convertToDecimal() -> Decimal? {
        Decimal(Double(self))
    }

    public func convertToString() -> String? {
        "\(self)"
    }

    public func convertToDouble() -> Double? {
        Double(self)
    }

    public func convertToFloat() -> Float? {
        self
    }

    public func convertToBool() -> Bool? {
        self == 1 ? true : (self == 0 ? false : nil)
    }
}
```

- [ ] **Step 3: Teach single-value decoding to return `Float` targets**

Update the scalar branch inside `tryMakeWrapperValue(...)` to include `Float`:

```swift
if let single = try? container.decode(SingleValue.self), let raw = single.raw {
    rawValue = raw
    if T.self == Int.self {
        value = single.value(Int.self) as? T
    } else if T.self == Decimal.self {
        value = single.value(Decimal.self) as? T
    } else if T.self == Double.self {
        value = single.value(Double.self) as? T
    } else if T.self == Float.self {
        value = single.value(Float.self) as? T
    } else if T.self == String.self {
        value = single.value(String.self) as? T
    } else if T.self == Bool.self {
        value = single.value(Bool.self) as? T
    }
}
```

- [ ] **Step 4: Run the focused tests to verify they pass**

Run:
```bash
swift test --filter DefaultValueTests
```

Expected: PASS for the new Float provider and scalar conversion tests. Existing `DefaultValueTests` should also remain green.

- [ ] **Step 5: Commit the scalar Float support**

```bash
git add Classes/Core/Codable/ValueWrapper/DefaultValue.swift Project/RYKitTests/ValueWrapperTests.swift
git commit -m "feat: add DefaultValue float scalar support"
```

### Task 3: Add failing tests for Float collections and Double-backed decoding paths

**Files:**
- Modify: `Project/RYKitTests/ValueWrapperTests.swift:20-192`
- Test: `Project/RYKitTests/ValueWrapperTests.swift`

- [ ] **Step 1: Add failing collection and Double-backed conversion tests**

Add these test methods inside `final class DefaultValueTests: XCTestCase`:

```swift
func test_decode_doubleToFloat_converts() throws {
    let json = """
    {"intValue": 0, "boolValue": false, "stringValue": "", "doubleValue": 0, "decimalValue": 0, "floatValue": 3.75}
    """
    let model = try decode(DefaultValueModel.self, from: json)

    XCTAssertEqual(model.floatValue, 3.75, accuracy: 0.0001)
}

func test_decode_decimalToFloat_converts() throws {
    let json = """
    {"intValue": 0, "boolValue": false, "stringValue": "", "doubleValue": 0, "decimalValue": 0, "floatValue": "4.5"}
    """
    let model = try decode(DefaultValueModel.self, from: json)

    XCTAssertEqual(model.floatValue, 4.5, accuracy: 0.0001)
}

func test_decode_floatArray_convertsElements() throws {
    let json = """
    {"floatArray": [1, "2.5", true, 3.75]}
    """
    let model = try decode(DefaultValueFloatCollectionModel.self, from: json)

    XCTAssertEqual(model.floatArray.count, 4)
    XCTAssertEqual(model.floatArray[0], 1, accuracy: 0.0001)
    XCTAssertEqual(model.floatArray[1], 2.5, accuracy: 0.0001)
    XCTAssertEqual(model.floatArray[2], 1, accuracy: 0.0001)
    XCTAssertEqual(model.floatArray[3], 3.75, accuracy: 0.0001)
}

func test_decode_floatDictionary_convertsValues() throws {
    let json = """
    {"floatDictionary": {"a": 1, "b": "2.5", "c": false, "d": 4.25}}
    """
    let model = try decode(DefaultValueFloatCollectionModel.self, from: json)

    XCTAssertEqual(model.floatDictionary["a"], 1, accuracy: 0.0001)
    XCTAssertEqual(model.floatDictionary["b"], 2.5, accuracy: 0.0001)
    XCTAssertEqual(model.floatDictionary["c"], 0, accuracy: 0.0001)
    XCTAssertEqual(model.floatDictionary["d"], 4.25, accuracy: 0.0001)
}
```

- [ ] **Step 2: Run the focused tests to verify they fail**

Run:
```bash
swift test --filter DefaultValueTests
```

Expected: FAIL on the new collection tests because `[Float]` and `[String: Float]` are not yet handled by `tryMakeWrapperValue(...)`.

- [ ] **Step 3: Commit the failing collection tests**

```bash
git add Project/RYKitTests/ValueWrapperTests.swift
git commit -m "test: add failing DefaultValue float collection tests"
```

### Task 4: Implement Float collection conversion while keeping Double as the float pipeline

**Files:**
- Modify: `Classes/Core/Codable/ValueWrapper/DefaultValue.swift:82-154`
- Test: `Project/RYKitTests/ValueWrapperTests.swift`

- [ ] **Step 1: Add `[Float]` support to the array conversion branch**

Update the array branch in `tryMakeWrapperValue(...)`:

```swift
if T.self is ArrayType.Type {
    if let array = try? container.decode(CodableArray.self).array {
        rawValue = array
        if T.self == [Int].self {
            value = array.compactMap {
                convert(value: $0, toType:Int.self)
            } as? T
        } else if T.self == [Decimal].self {
            value = array.compactMap {
                convert(value: $0, toType:Decimal.self)
            } as? T
        } else if T.self == [Double].self {
            value = array.compactMap {
                convert(value: $0, toType:Double.self)
            } as? T
        } else if T.self == [Float].self {
            value = array.compactMap {
                convert(value: $0, toType:Float.self)
            } as? T
        } else if T.self == [String].self {
            value = array.compactMap {
                convert(value: $0, toType:String.self)
            } as? T
        }
    }
}
```

- [ ] **Step 2: Add `[String: Float]` support to the dictionary conversion branch**

Update the dictionary branch in `tryMakeWrapperValue(...)`:

```swift
if let dic = try? container.decode(CodableDictionary.self).dictionary {
    rawValue = dic
    if T.self == [String: Int].self {
        value = dic.compactMapValues {
            convert(value: $0, toType:Int.self)
        } as? T
    } else if T.self == [String: Decimal].self {
        value = dic.compactMapValues {
            convert(value: $0, toType:Decimal.self)
        } as? T
    } else if T.self == [String: Double].self {
        value = dic.compactMapValues {
            convert(value: $0, toType:Double.self)
        } as? T
    } else if T.self == [String: Float].self {
        value = dic.compactMapValues {
            convert(value: $0, toType:Float.self)
        } as? T
    } else if T.self == [String: String].self {
        value = dic.compactMapValues {
            convert(value: $0, toType:String.self)
        } as? T
    }
}
```

- [ ] **Step 3: Keep `SingleValue` on the existing Double-centric raw path**

Do not add a new `Float` raw decoding branch. Keep this order, which preserves the current floating-point pipeline centered on `Double`:

```swift
public init(from decoder: any Decoder) throws {
    let container = try decoder.singleValueContainer()
    if let value = try? container.decode(Bool.self) {
       raw = value
    } else if let value = try? container.decode(Int.self) {
        raw = value
    } else if let value = try? container.decode(Decimal.self) {
        raw = value
    } else if let value = try? container.decode(String.self) {
        raw = value
    } else if let value = try? container.decode(Double.self) {
        raw = value
    } else {
        raw = nil
    }
}
```

- [ ] **Step 4: Run the focused tests to verify they pass**

Run:
```bash
swift test --filter DefaultValueTests
```

Expected: PASS for the new array and dictionary Float tests, while all previous `DefaultValueTests` remain green.

- [ ] **Step 5: Commit the collection Float support**

```bash
git add Classes/Core/Codable/ValueWrapper/DefaultValue.swift Project/RYKitTests/ValueWrapperTests.swift
git commit -m "feat: add DefaultValue float collection support"
```

### Task 5: Run regression verification and finalize

**Files:**
- Modify: `Classes/Core/Codable/ValueWrapper/DefaultValue.swift`
- Modify: `Project/RYKitTests/ValueWrapperTests.swift`
- Test: `Project/RYKitTests/ValueWrapperTests.swift`

- [ ] **Step 1: Run the full test suite**

Run:
```bash
swift test
```

Expected: PASS with the package test suite green, including `DefaultValueTests`, `PreferValueTests`, and the rest of the existing wrappers tests.

- [ ] **Step 2: Inspect the final diff**

Run:
```bash
git diff -- Classes/Core/Codable/ValueWrapper/DefaultValue.swift Project/RYKitTests/ValueWrapperTests.swift
```

Expected: Diff shows only the planned Float provider, conversion logic, and tests. No unrelated refactors or file moves.

- [ ] **Step 3: Commit the final verification state if needed**

```bash
git add Classes/Core/Codable/ValueWrapper/DefaultValue.swift Project/RYKitTests/ValueWrapperTests.swift
git commit -m "test: verify DefaultValue float support"
```

If there are no new changes after Step 2, skip this commit.

---

## Self-Review

- **Spec coverage:** The plan covers the public API (`FloatZero` provider and alias), scalar conversion (`String`/`Int`/`Double`/`Decimal`/`Bool` -> `Float`), collection conversion (`[Float]`, `[String: Float]`), default-value fallback semantics, and regression verification.
- **Placeholder scan:** No `TBD`, `TODO`, “similar to”, or vague “add tests” instructions remain. Each code-changing step includes concrete code blocks and each verification step includes exact commands plus expected outcomes.
- **Type consistency:** The plan consistently uses `FloatZero`, `convertToFloat()`, `DefaultValueFloatCollectionModel`, `[Float]`, and `[String: Float]`. It also keeps the internal raw floating-point path centered on `Double`, matching the approved design.
