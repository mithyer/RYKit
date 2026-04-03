# CollectionValue Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Complete `CollectionValue` so `[Any]?` and `[String: Any]?` can be decoded/encoded via `CodableArray`/`CodableDictionary` with fail-to-`nil` decode behavior and omit-key-on-`nil` keyed encode behavior.

**Architecture:** Keep a single generic wrapper `CollectionValue<T: AnyCollectionValue>` and branch at runtime for the two supported concrete types. Reuse existing `CodableArray` and `CodableDictionary` as the serialization bridge instead of reimplementing any `Any` collection parsing. Align keyed decoding/encoding extension behavior with existing wrappers (`PreferValue`, `FromStringValue`) so missing keys decode to empty wrapper and `nil` values are omitted during keyed encoding.

**Tech Stack:** Swift, Codable, XCTest, Swift Package Manager (`swift test`)

---

## File Structure And Responsibilities

- Modify: `Classes/Core/Codable/ValueWrapper/CollectionValue.swift`
  - Implement wrapper init/encode/decode/description.
  - Add keyed decoding + keyed encoding container extensions.
- Modify: `Project/RYKitTests/ValueWrapperTests.swift`
  - Add collection wrapper test models and `CollectionValueTests`.
  - Cover decode success/fail and encode success/omit/error cases.
- Reference: `Classes/Core/Codable/Codable+Any.swift`
  - Existing `CodableArray` / `CodableDictionary` encoding and failure semantics.

### Task 1: Add Failing CollectionValue Decode Tests (TDD)

**Files:**
- Modify: `Project/RYKitTests/ValueWrapperTests.swift`
- Reference: `Classes/Core/Codable/ValueWrapper/CollectionValue.swift`

- [ ] **Step 1: Add collection test models near existing wrapper models**

```swift
private struct CollectionArrayModel: Codable {
    @CollectionValue var items: [Any]?
}

private struct CollectionDictionaryModel: Codable {
    @CollectionValue var metadata: [String: Any]?
}
```

- [ ] **Step 2: Add decode-focused test cases in new `CollectionValueTests`**

```swift
func test_decode_array_success() throws {
    let json = #"{"items":[1,"two",true,{"k":"v"}]}"#
    let model = try decode(CollectionArrayModel.self, from: json)
    XCTAssertEqual(model.items?.count, 4)
    XCTAssertEqual(model.items?[0] as? Int, 1)
}

func test_decode_dictionary_success() throws {
    let json = #"{"metadata":{"id":1,"name":"ray","ok":true}}"#
    let model = try decode(CollectionDictionaryModel.self, from: json)
    XCTAssertEqual(model.metadata?["id"] as? Int, 1)
    XCTAssertEqual(model.metadata?["name"] as? String, "ray")
}

func test_decode_missingKey_returnsNil() throws {
    let model = try decode(CollectionDictionaryModel.self, from: "{}")
    XCTAssertNil(model.metadata)
}

func test_decode_null_returnsNil() throws {
    let json = #"{"metadata":null}"#
    let model = try decode(CollectionDictionaryModel.self, from: json)
    XCTAssertNil(model.metadata)
}

func test_decode_typeMismatch_returnsNilWithoutThrow() throws {
    let json = #"{"items":{"not":"array"}}"#
    let model = try decode(CollectionArrayModel.self, from: json)
    XCTAssertNil(model.items)
}
```

- [ ] **Step 3: Run tests to confirm failure before implementation**

Run: `swift test --filter CollectionValueTests`  
Expected: FAIL with compile errors or unresolved `CollectionValue` Codable behavior.

- [ ] **Step 4: Commit failing tests**

```bash
git add Project/RYKitTests/ValueWrapperTests.swift
git commit -m "test: add failing CollectionValue decode coverage"
```

### Task 2: Implement CollectionValue Wrapper And Container Extensions

**Files:**
- Modify: `Classes/Core/Codable/ValueWrapper/CollectionValue.swift`
- Reference: `Classes/Core/Codable/Codable+Any.swift`

- [ ] **Step 1: Implement wrapper API and description**

```swift
public var description: String { String(describing: wrappedValue) }

public init() {}

public init(wrappedValue: T?) {
    self.wrappedValue = wrappedValue
}
```

- [ ] **Step 2: Implement decoding with fail-to-`nil` behavior**

```swift
public init(from decoder: Decoder) throws {
    let container = try decoder.singleValueContainer()
    if container.decodeNil() {
        wrappedValue = nil
        return
    }
    if T.self == [Any].self,
       let array = try? container.decode(CodableArray.self).array as? T {
        wrappedValue = array
        return
    }
    if T.self == [String: Any].self,
       let dic = try? container.decode(CodableDictionary.self).dictionary as? T {
        wrappedValue = dic
        return
    }
    wrappedValue = nil
}
```

- [ ] **Step 3: Implement encoding and keyed container extensions**

```swift
public func encode(to encoder: Encoder) throws {
    guard let wrappedValue else { return }
    var container = encoder.singleValueContainer()
    if let array = wrappedValue as? [Any] {
        try container.encode(CodableArray(array))
    } else if let dic = wrappedValue as? [String: Any] {
        try container.encode(CodableDictionary(dic))
    }
}

public extension KeyedDecodingContainer {
    func decode<T>(_ type: CollectionValue<T>.Type, forKey key: Key) throws -> CollectionValue<T> {
        if let value = try decodeIfPresent(CollectionValue<T>.self, forKey: key) {
            return value
        }
        return CollectionValue()
    }
}

public extension KeyedEncodingContainer {
    mutating func encode<T>(_ value: CollectionValue<T>, forKey key: Key) throws {
        guard value.wrappedValue != nil else { return }
        if let array = value.wrappedValue as? [Any] {
            try encode(array, forKey: key)
            return
        }
        if let dic = value.wrappedValue as? [String: Any] {
            try encode(dic, forKey: key)
            return
        }
    }
}
```

- [ ] **Step 4: Run decode tests again**

Run: `swift test --filter CollectionValueTests/test_decode`  
Expected: PASS for all decode tests added in Task 1.

- [ ] **Step 5: Commit implementation**

```bash
git add Classes/Core/Codable/ValueWrapper/CollectionValue.swift
git commit -m "feat: implement CollectionValue decode and keyed encode/decode"
```

### Task 3: Add Encode Behavior Tests And Error Propagation Test

**Files:**
- Modify: `Project/RYKitTests/ValueWrapperTests.swift`
- Reference: `Classes/Core/Codable/Codable+Any.swift`

- [ ] **Step 1: Add encode success and omit-key tests**

```swift
func test_encode_array_success() throws {
    let model = CollectionArrayModel(items: .init(wrappedValue: [1, "two", true]))
    let data = try JSONEncoder().encode(model)
    let dict = try JSONSerialization.jsonObject(with: data) as! [String: Any]
    let items = try XCTUnwrap(dict["items"] as? [Any])
    XCTAssertEqual(items.count, 3)
}

func test_encode_dictionary_success() throws {
    let model = CollectionDictionaryModel(metadata: .init(wrappedValue: ["id": 1, "name": "ray"]))
    let data = try JSONEncoder().encode(model)
    let dict = try JSONSerialization.jsonObject(with: data) as! [String: Any]
    XCTAssertEqual((dict["metadata"] as? [String: Any])?["id"] as? Int, 1)
}

func test_encode_nil_omitsKey() throws {
    let model = CollectionDictionaryModel(metadata: .init(wrappedValue: nil))
    let data = try JSONEncoder().encode(model)
    let dict = try JSONSerialization.jsonObject(with: data) as! [String: Any]
    XCTAssertNil(dict["metadata"])
}
```

- [ ] **Step 2: Add payload-level invalid encode value test**

```swift
func test_encode_invalidPayload_throwsEncodingError() {
    let invalid: [String: Any] = ["date": Date()]
    let model = CollectionDictionaryModel(metadata: .init(wrappedValue: invalid))

    XCTAssertThrowsError(try JSONEncoder().encode(model)) { error in
        XCTAssertTrue(error is EncodingError)
    }
}
```

- [ ] **Step 3: Run focused tests**

Run: `swift test --filter CollectionValueTests`  
Expected: PASS for all `CollectionValueTests`.

- [ ] **Step 4: Run full wrapper regression tests**

Run: `swift test`  
Expected: PASS without regressions.

- [ ] **Step 5: Commit encode test coverage**

```bash
git add Project/RYKitTests/ValueWrapperTests.swift
git commit -m "test: add CollectionValue encode and error propagation coverage"
```

### Task 4: Final Verification And Cleanup

**Files:**
- Verify: `Classes/Core/Codable/ValueWrapper/CollectionValue.swift`
- Verify: `Project/RYKitTests/ValueWrapperTests.swift`

- [ ] **Step 1: Review diffs for scope control**

Run: `git diff -- Classes/Core/Codable/ValueWrapper/CollectionValue.swift Project/RYKitTests/ValueWrapperTests.swift`  
Expected: Only planned behavior and tests are changed.

- [ ] **Step 2: Run final test confirmation**

Run: `swift test --filter CollectionValueTests`  
Expected: PASS.

- [ ] **Step 3: Prepare branch summary commit (if needed)**

```bash
git add Classes/Core/Codable/ValueWrapper/CollectionValue.swift Project/RYKitTests/ValueWrapperTests.swift
git commit -m "feat: complete CollectionValue wrapper behavior"
```

- [ ] **Step 4: Record completion notes in PR/summary**

Include:
- decode fail-to-`nil` semantics
- keyed encode omit-key-on-`nil` semantics
- invalid payload encode error propagation semantics
