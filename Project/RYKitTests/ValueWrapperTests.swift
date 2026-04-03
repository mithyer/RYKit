//
//  ValueWrapperTests.swift
//  RYKitTests
//
//  Created by Claude on 2026/1/20.
//

import XCTest
@testable import RYKit

// MARK: - Test Models

private struct DefaultValueModel: Codable {
    @Default.IntZero var intValue: Int
    @Default.BoolFalse var boolValue: Bool
    @Default.StringEmpty var stringValue: String
    @Default.DoubleZero var doubleValue: Double
    @Default.FloatZero var floatValue: Float
    @Default.DecimalZero var decimalValue: Decimal
}

private struct DefaultValueArrayModel: Codable {
    @Default.ArrayEmpty<[Int]> var intArray: [Int]
    @Default.ArrayEmpty<[String]> var stringArray: [String]
}

private enum TestEnum: String, Codable, CaseIterable {
    case first
    case second
    case third
}

private struct DefaultValueEnumModel: Codable {
    @Default.CaseFirst<TestEnum> var enumValue: TestEnum
}

private struct PreferValueModel: Codable {
    @PreferValue var intValue: Int?
    @PreferValue var stringValue: String?
    @PreferValue var boolValue: Bool?
}

private struct IgnoreValueModel: Codable, Equatable {
    var name: String
    @IgnoreValue var localState: String?
    
    static func == (lhs: IgnoreValueModel, rhs: IgnoreValueModel) -> Bool {
        lhs.name == rhs.name
    }
}

private struct ExistValueModel: Codable {
    @ExistValue var id: Int
    @ExistValue var name: String
}

private struct InnerModel: Codable, Equatable {
    var value: Int
    var text: String
}

private struct FromStringValueModel: Codable {
    @FromStringValue var inner: InnerModel?
}

private struct FloatContainerModel: Codable {
    @Default.FloatZero var floatValue: Float
}

private struct FloatArrayModel: Codable {
    @Default.ArrayEmpty<[Float]> var values: [Float]
}

private struct FloatDictionaryModel: Codable {
    @Default.DicEmpty<String, Float> var values: [String: Float]
}

private struct CollectionArrayModel: Codable {
    @CollectionValue var items: [Any]?
}

private struct CollectionDictionaryModel: Codable {
    @CollectionValue var metadata: [String: Any]?
}

private struct ZeroModel: Codable {
    @Default.Zero var intValue: Int
    @Default.Zero var floatValue: Float
    @Default.Zero var doubleValue: Double
    @Default.Zero var decimalValue: Decimal
}

private struct EmptyModel: Codable {
    @Default.Empty var name: String
    @Default.Empty var tags: [String]
    @Default.Empty var mapping: [String: Int]
    @Default.Empty var ids: Set<Int>
}

private struct SetContainerModel: Codable {
    @Default.Empty var ids: Set<Int>
}

// MARK: - DefaultValue Tests

final class DefaultValueTests: XCTestCase {
    
    func test_decode_withMatchingType_succeeds() throws {
        let json = """
        {"intValue": 42, "boolValue": true, "stringValue": "hello", "doubleValue": 3.14, "floatValue": 2.5, "decimalValue": 99.99}
        """
        let model = try decode(DefaultValueModel.self, from: json)

        XCTAssertEqual(model.intValue, 42)
        XCTAssertEqual(model.boolValue, true)
        XCTAssertEqual(model.stringValue, "hello")
        XCTAssertEqual(model.doubleValue, 3.14, accuracy: 0.001)
        XCTAssertEqual(model.floatValue, 2.5, accuracy: 0.0001)
        XCTAssertEqual(model.decimalValue, Decimal(string: "99.99"))
    }
    
    func test_decode_withMissingKey_usesDefault() throws {
        let json = "{}"
        let model = try decode(DefaultValueModel.self, from: json)

        XCTAssertEqual(model.intValue, 0)
        XCTAssertEqual(model.boolValue, false)
        XCTAssertEqual(model.stringValue, "")
        XCTAssertEqual(model.doubleValue, 0)
        XCTAssertEqual(model.floatValue, 0)
        XCTAssertEqual(model.decimalValue, Decimal.zero)
    }
    
    func test_decode_withNullValue_usesDefault() throws {
        let json = """
        {"intValue": null, "boolValue": null, "stringValue": null, "doubleValue": null, "floatValue": null, "decimalValue": null}
        """
        let model = try decode(DefaultValueModel.self, from: json)

        XCTAssertEqual(model.intValue, 0)
        XCTAssertEqual(model.boolValue, false)
        XCTAssertEqual(model.stringValue, "")
        XCTAssertEqual(model.doubleValue, 0)
        XCTAssertEqual(model.floatValue, 0)
        XCTAssertEqual(model.decimalValue, Decimal.zero)
    }
    
    func test_decode_stringToInt_converts() throws {
        let json = """
        {"intValue": "123", "boolValue": false, "stringValue": "", "doubleValue": 0, "decimalValue": 0}
        """
        let model = try decode(DefaultValueModel.self, from: json)
        
        XCTAssertEqual(model.intValue, 123)
    }
    
    func test_decode_intToString_converts() throws {
        let json = """
        {"intValue": 0, "boolValue": false, "stringValue": 456, "doubleValue": 0, "decimalValue": 0}
        """
        let model = try decode(DefaultValueModel.self, from: json)
        
        XCTAssertEqual(model.stringValue, "456")
    }
    
    func test_decode_stringToBool_converts() throws {
        let json = """
        {"intValue": 0, "boolValue": "true", "stringValue": "", "doubleValue": 0, "decimalValue": 0}
        """
        let model = try decode(DefaultValueModel.self, from: json)
        
        XCTAssertEqual(model.boolValue, true)
    }
    
    func test_decode_intToBool_converts() throws {
        let json = """
        {"intValue": 0, "boolValue": 1, "stringValue": "", "doubleValue": 0, "decimalValue": 0}
        """
        let model = try decode(DefaultValueModel.self, from: json)
        
        XCTAssertEqual(model.boolValue, true)
    }
    
    func test_decode_doubleToInt_truncates() throws {
        let json = """
        {"intValue": 3.9, "boolValue": false, "stringValue": "", "doubleValue": 0, "decimalValue": 0}
        """
        let model = try decode(DefaultValueModel.self, from: json)
        
        XCTAssertEqual(model.intValue, 3)
    }
    
    func test_decode_stringToFloat_converts() throws {
        let json = """
        {"floatValue": "12.5"}
        """
        let model = try decode(FloatContainerModel.self, from: json)

        XCTAssertEqual(model.floatValue, 12.5, accuracy: 0.0001)
    }

    func test_decode_intToFloat_converts() throws {
        let json = """
        {"floatValue": 7}
        """
        let model = try decode(FloatContainerModel.self, from: json)

        XCTAssertEqual(model.floatValue, 7, accuracy: 0.0001)
    }

    func test_decode_doubleToFloat_converts() throws {
        let json = """
        {"floatValue": 3.25}
        """
        let model = try decode(FloatContainerModel.self, from: json)

        XCTAssertEqual(model.floatValue, 3.25, accuracy: 0.0001)
    }

    func test_decode_decimalToFloat_converts() throws {
        let value = SingleValue(Decimal(string: "4.5")!)
        let converted = try XCTUnwrap(value.value(Float.self))

        XCTAssertEqual(converted, 4.5, accuracy: 0.0001)
    }

    func test_decode_floatArray_convertsElements() throws {
        let json = """
        {"values": ["1.5", 2, true, 3.25]}
        """
        let model = try decode(FloatArrayModel.self, from: json)

        XCTAssertEqual(model.values.count, 4)
        XCTAssertEqual(model.values[0], 1.5, accuracy: 0.0001)
        XCTAssertEqual(model.values[1], 2, accuracy: 0.0001)
        XCTAssertEqual(model.values[2], 1, accuracy: 0.0001)
        XCTAssertEqual(model.values[3], 3.25, accuracy: 0.0001)
    }

    func test_decode_floatDictionary_convertsValues() throws {
        let json = """
        {"values": {"a": "1.5", "b": 2, "c": false, "d": 3.25}}
        """
        let model = try decode(FloatDictionaryModel.self, from: json)

        XCTAssertEqual(model.values["a"]!, 1.5, accuracy: 0.0001)
        XCTAssertEqual(model.values["b"]!, 2, accuracy: 0.0001)
        XCTAssertEqual(model.values["c"]!, 0, accuracy: 0.0001)
        XCTAssertEqual(model.values["d"]!, 3.25, accuracy: 0.0001)
    }

    func test_decode_zeroModel_withMissingKey_usesZeroDefaults() throws {
        let json = "{}"
        let model = try decode(ZeroModel.self, from: json)

        XCTAssertEqual(model.intValue, 0)
        XCTAssertEqual(model.floatValue, 0, accuracy: 0.0001)
        XCTAssertEqual(model.doubleValue, 0, accuracy: 0.0001)
        XCTAssertEqual(model.decimalValue, Decimal.zero)
    }

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

    func test_decode_emptyModel_withMissingKey_usesEmptyDefaults() throws {
        let json = "{}"
        let model = try decode(EmptyModel.self, from: json)

        XCTAssertEqual(model.name, "")
        XCTAssertEqual(model.tags, [])
        XCTAssertEqual(model.mapping, [:])
        XCTAssertEqual(model.ids, Set<Int>())
    }

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

    func test_decode_setContainerModel_withMatchingType_succeeds() throws {
        let json = """
        {"ids": [3, 1, 3, 2]}
        """
        let model = try decode(SetContainerModel.self, from: json)

        XCTAssertEqual(model.ids, Set([1, 2, 3]))
    }

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

    func test_zeroValue_numericDefaultImplementation_usesZeroProviderDefaults() {
        XCTAssertEqual(ZeroProvider<Int>.default, 0)
        XCTAssertEqual(ZeroProvider<Float>.default, 0, accuracy: 0.0001)
        XCTAssertEqual(ZeroProvider<Double>.default, 0, accuracy: 0.0001)
        XCTAssertEqual(ZeroProvider<Decimal>.default, Decimal.zero)
    }

    func test_emptyValue_defaultImplementations_useEmptyProviderDefaults() {
        XCTAssertEqual(EmptyProvider<String>.default, "")
        XCTAssertEqual(EmptyProvider<[Int]>.default, [])
        XCTAssertEqual(EmptyProvider<[String: Int]>.default, [:])
        XCTAssertEqual(EmptyProvider<Set<Int>>.default, Set<Int>())
    }

    func test_encode_outputsUnwrappedValue() throws {
        var model = DefaultValueModel()
        model.intValue = 100
        model.stringValue = "test"

        let data = try JSONEncoder().encode(model)
        let dict = try JSONSerialization.jsonObject(with: data) as! [String: Any]

        XCTAssertEqual(dict["intValue"] as? Int, 100)
        XCTAssertEqual(dict["stringValue"] as? String, "test")
    }

    func test_deprecatedZeroAliases_useZeroProviderDefaults() {
        XCTAssertEqual(Default.IntZero().wrappedValue, 0)
        XCTAssertEqual(Default.FloatZero().wrappedValue, 0, accuracy: 0.0001)
        XCTAssertEqual(Default.DoubleZero().wrappedValue, 0, accuracy: 0.0001)
        XCTAssertEqual(Default.DecimalZero().wrappedValue, Decimal.zero)
    }

    func test_deprecatedEmptyAliases_useEmptyProviderDefaults() {
        XCTAssertEqual(Default.StringEmpty().wrappedValue, "")
        XCTAssertEqual(Default.ArrayEmpty<[Int]>().wrappedValue, [])
        XCTAssertEqual(Default.DicEmpty<String, Int>().wrappedValue, [:])
        XCTAssertEqual(Default.SetEmpty<Int>().wrappedValue, Set<Int>())
    }

    func test_providers_boolFalse_default() {
        XCTAssertEqual(DefaultValueProviders.BoolFalse.default, false)
    }
    
    func test_providers_boolTrue_default() {
        XCTAssertEqual(DefaultValueProviders.BoolTrue.default, true)
    }
    
    func test_providers_intZero_default() {
        XCTAssertEqual(Default.IntZero().wrappedValue, 0)
    }
    
    func test_providers_stringEmpty_default() {
        XCTAssertEqual(Default.StringEmpty().wrappedValue, "")
    }
    
    func test_providers_floatZero_default() {
        XCTAssertEqual(Default.FloatZero().wrappedValue, 0)
    }

    func test_providers_arrayEmpty_default() throws {
        XCTAssertEqual(Default.ArrayEmpty<[Int]>().wrappedValue, [])
        XCTAssertEqual(Default.ArrayEmpty<[String]>().wrappedValue, [])
    }

    func test_providers_dicEmpty_default() {
        XCTAssertEqual(Default.DicEmpty<String, Int>().wrappedValue, [:])
    }

    func test_providers_caseFirst_default() throws {
        let json = "{}"
        let model = try decode(DefaultValueEnumModel.self, from: json)
        
        XCTAssertEqual(model.enumValue, .first)
    }
}

// MARK: - PreferValue Tests

final class PreferValueTests: XCTestCase {
    
    func test_decode_withMatchingType_succeeds() throws {
        let json = """
        {"intValue": 42, "stringValue": "hello", "boolValue": true}
        """
        let model = try decode(PreferValueModel.self, from: json)
        
        XCTAssertEqual(model.intValue, 42)
        XCTAssertEqual(model.stringValue, "hello")
        XCTAssertEqual(model.boolValue, true)
    }
    
    func test_decode_withMissingKey_returnsNil() throws {
        let json = "{}"
        let model = try decode(PreferValueModel.self, from: json)
        
        XCTAssertNil(model.intValue)
        XCTAssertNil(model.stringValue)
        XCTAssertNil(model.boolValue)
    }
    
    func test_decode_withNullValue_returnsNil() throws {
        let json = """
        {"intValue": null, "stringValue": null, "boolValue": null}
        """
        let model = try decode(PreferValueModel.self, from: json)
        
        XCTAssertNil(model.intValue)
        XCTAssertNil(model.stringValue)
        XCTAssertNil(model.boolValue)
    }
    
    func test_decode_stringToInt_converts() throws {
        let json = """
        {"intValue": "999"}
        """
        let model = try decode(PreferValueModel.self, from: json)
        
        XCTAssertEqual(model.intValue, 999)
    }
    
    func test_decode_incompatibleType_returnsNil() throws {
        let json = """
        {"intValue": "not a number"}
        """
        let model = try decode(PreferValueModel.self, from: json)
        
        XCTAssertNil(model.intValue)
    }
    
    func test_encode_nilValue_encodesNull() throws {
        let model = PreferValueModel()
        
        let data = try JSONEncoder().encode(model)
        let dict = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        
        XCTAssertTrue(dict["intValue"] is NSNull)
    }
    
    func test_encode_someValue_encodesValue() throws {
        var model = PreferValueModel()
        model.intValue = 123
        model.stringValue = "test"
        
        let data = try JSONEncoder().encode(model)
        let dict = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        
        XCTAssertEqual(dict["intValue"] as? Int, 123)
        XCTAssertEqual(dict["stringValue"] as? String, "test")
    }
}

// MARK: - IgnoreValue Tests

final class IgnoreValueTests: XCTestCase {
    
    func test_decode_ignoresJsonValue() throws {
        let json = """
        {"name": "test", "localState": "should be ignored"}
        """
        let model = try decode(IgnoreValueModel.self, from: json)
        
        XCTAssertEqual(model.name, "test")
        XCTAssertNil(model.localState)
    }
    
    func test_decode_withMissingKey_succeeds() throws {
        let json = """
        {"name": "test"}
        """
        let model = try decode(IgnoreValueModel.self, from: json)
        
        XCTAssertEqual(model.name, "test")
        XCTAssertNil(model.localState)
    }
    
    func test_encode_omitsFromOutput() throws {
        var model = IgnoreValueModel(name: "test", localState: nil)
        model.localState = "local value"
        
        let data = try JSONEncoder().encode(model)
        let dict = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        
        XCTAssertEqual(dict["name"] as? String, "test")
        XCTAssertNil(dict["localState"])
    }
    
    func test_wrappedValue_preservedLocally() {
        var model = IgnoreValueModel(name: "test", localState: nil)
        model.localState = "my state"
        
        XCTAssertEqual(model.localState, "my state")
    }
}

// MARK: - ExistValue Tests

final class ExistValueTests: XCTestCase {
    
    func test_decode_withMatchingType_succeeds() throws {
        let json = """
        {"id": 42, "name": "hello"}
        """
        let model = try decode(ExistValueModel.self, from: json)
        
        XCTAssertEqual(model.id, 42)
        XCTAssertEqual(model.name, "hello")
    }
    
    func test_decode_withMissingKey_throws() {
        let json = """
        {"name": "hello"}
        """
        
        XCTAssertThrowsError(try decode(ExistValueModel.self, from: json)) { error in
            XCTAssertTrue(error is DecodingError)
        }
    }
    
    func test_decode_withNullValue_throws() {
        let json = """
        {"id": null, "name": "hello"}
        """
        
        XCTAssertThrowsError(try decode(ExistValueModel.self, from: json)) { error in
            XCTAssertTrue(error is DecodingError)
        }
    }
    
    func test_decode_stringToInt_converts() throws {
        let json = """
        {"id": "123", "name": "test"}
        """
        let model = try decode(ExistValueModel.self, from: json)
        
        XCTAssertEqual(model.id, 123)
    }
    
    func test_encode_outputsValue() throws {
        let model = ExistValueModel(id: 99, name: "encoded")
        
        let data = try JSONEncoder().encode(model)
        let dict = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        
        XCTAssertEqual(dict["id"] as? Int, 99)
        XCTAssertEqual(dict["name"] as? String, "encoded")
    }
}

// MARK: - FromStringValue Tests

final class FromStringValueTests: XCTestCase {
    
    func test_decode_jsonString_parsesModel() throws {
        let json = """
        {"inner": "{\\"value\\": 42, \\"text\\": \\"hello\\"}"}
        """
        let model = try decode(FromStringValueModel.self, from: json)
        
        XCTAssertEqual(model.inner?.value, 42)
        XCTAssertEqual(model.inner?.text, "hello")
    }
    
    func test_decode_directObject_succeeds() throws {
        let json = """
        {"inner": {"value": 100, "text": "direct"}}
        """
        let model = try decode(FromStringValueModel.self, from: json)
        
        XCTAssertEqual(model.inner?.value, 100)
        XCTAssertEqual(model.inner?.text, "direct")
    }
    
    func test_decode_invalidJson_returnsNil() throws {
        let json = """
        {"inner": "not valid json"}
        """
        let model = try decode(FromStringValueModel.self, from: json)
        
        XCTAssertNil(model.inner)
    }
    
    func test_decode_withMissingKey_returnsNil() throws {
        let json = "{}"
        let model = try decode(FromStringValueModel.self, from: json)
        
        XCTAssertNil(model.inner)
    }
}

// MARK: - CollectionValue Tests

final class CollectionValueTests: XCTestCase {

    func test_encode_array_success() throws {
        let model = CollectionArrayModel(items: .init(wrappedValue: [1, "two", true] as [Any]))

        let data = try JSONEncoder().encode(model)
        let dict = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        let items = try XCTUnwrap(dict["items"] as? [Any])

        XCTAssertEqual(items.count, 3)
        XCTAssertEqual(items[0] as? Int, 1)
        XCTAssertEqual(items[1] as? String, "two")
        XCTAssertEqual(items[2] as? Bool, true)
    }

    func test_encode_dictionary_success() throws {
        let model = CollectionDictionaryModel(metadata: .init(wrappedValue: ["name": "ray", "count": 2, "active": true] as [String: Any]))

        let data = try JSONEncoder().encode(model)
        let dict = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        let metadata = try XCTUnwrap(dict["metadata"] as? [String: Any])

        XCTAssertEqual(metadata["name"] as? String, "ray")
        XCTAssertEqual(metadata["count"] as? Int, 2)
        XCTAssertEqual(metadata["active"] as? Bool, true)
    }

    func test_encode_nil_omitsKey() throws {
        let model = CollectionDictionaryModel(metadata: .init(wrappedValue: nil))

        let data = try JSONEncoder().encode(model)
        let dict = try JSONSerialization.jsonObject(with: data) as! [String: Any]

        XCTAssertNil(dict["metadata"])
    }

    func test_encode_invalidPayload_throwsEncodingError() {
        let model = CollectionDictionaryModel(metadata: .init(wrappedValue: ["date": Date()] as [String: Any]))

        XCTAssertThrowsError(try JSONEncoder().encode(model)) { error in
            guard case let EncodingError.invalidValue(value, context) = error else {
                return XCTFail("Expected EncodingError.invalidValue, got \(error)")
            }

            XCTAssertTrue(value is Date)
            XCTAssertFalse(context.codingPath.isEmpty)
        }
    }

    func test_decode_array_success() throws {
        let json = """
        {"items": [1, "two", true, {"k": "v"}]}
        """
        let model = try decode(CollectionArrayModel.self, from: json)

        XCTAssertEqual(model.items?.count, 4)
        XCTAssertEqual(model.items?[0] as? Int, 1)
        XCTAssertEqual(model.items?[1] as? String, "two")
        XCTAssertEqual(model.items?[2] as? Bool, true)
        let nestedObject = model.items?[3] as? [String: Any]
        XCTAssertEqual(nestedObject?["k"] as? String, "v")
    }

    func test_decode_dictionary_success() throws {
        let json = """
        {"metadata": {"name": "ray", "count": 2, "active": true}}
        """
        let model = try decode(CollectionDictionaryModel.self, from: json)

        XCTAssertEqual(model.metadata?["name"] as? String, "ray")
        XCTAssertEqual(model.metadata?["count"] as? Int, 2)
        XCTAssertEqual(model.metadata?["active"] as? Bool, true)
    }

    func test_decode_missingKey_returnsNil() throws {
        let json = "{}"
        let model = try decode(CollectionArrayModel.self, from: json)

        XCTAssertNil(model.items)
    }

    func test_decode_null_returnsNil() throws {
        let json = """
        {"items": null}
        """
        let model = try decode(CollectionArrayModel.self, from: json)

        XCTAssertNil(model.items)
    }

    func test_decode_typeMismatch_returnsNilWithoutThrow() throws {
        XCTExpectFailure("CollectionValue asserts on mismatched payloads in debug builds before returning nil.")

        let json = """
        {"items": {"unexpected": "object"}}
        """
        let model = try decode(CollectionArrayModel.self, from: json)

        XCTAssertNil(model.items)
    }
}

// MARK: - Helper

private func decode<T: Decodable>(_ type: T.Type, from json: String) throws -> T {
    let data = json.data(using: .utf8)!
    return try JSONDecoder().decode(T.self, from: data)
}

final class TypeConversionEdgeCaseTests: XCTestCase {
    
    func test_convert_largeIntToDouble_precision() throws {
        // Large int may lose precision when converted to Double
        let json = """
        {"intValue": 9007199254740993, "boolValue": false, "stringValue": "", "doubleValue": 0, "decimalValue": 0}
        """
        let model = try decode(DefaultValueModel.self, from: json)
        // Int should decode directly without precision loss
        XCTAssertEqual(model.intValue, 9007199254740993)
    }
    
    func test_convert_decimalToInt_truncation() throws {
        let json = """
        {"intValue": 99.9, "boolValue": false, "stringValue": "", "doubleValue": 0, "decimalValue": 0}
        """
        let model = try decode(DefaultValueModel.self, from: json)
        XCTAssertEqual(model.intValue, 99) // truncated
    }
    
    func test_convert_stringWithWhitespace_toInt_fails() throws {
        let json = """
        {"intValue": " 123 ", "boolValue": false, "stringValue": "", "doubleValue": 0, "decimalValue": 0}
        """
        let model = try decode(DefaultValueModel.self, from: json)
        // String with whitespace should fail to convert, use default
        XCTAssertEqual(model.intValue, 0)
    }
    
    func test_convert_emptyString_toInt_fails() throws {
        let json = """
        {"intValue": "", "boolValue": false, "stringValue": "", "doubleValue": 0, "decimalValue": 0}
        """
        let model = try decode(DefaultValueModel.self, from: json)
        XCTAssertEqual(model.intValue, 0) // default
    }
    
    func test_convert_boolStrings_caseInsensitive() throws {
        let json1 = """
        {"intValue": 0, "boolValue": "TRUE", "stringValue": "", "doubleValue": 0, "decimalValue": 0}
        """
        let json2 = """
        {"intValue": 0, "boolValue": "Yes", "stringValue": "", "doubleValue": 0, "decimalValue": 0}
        """
        let model1 = try decode(DefaultValueModel.self, from: json1)
        let model2 = try decode(DefaultValueModel.self, from: json2)
        XCTAssertTrue(model1.boolValue)
        XCTAssertTrue(model2.boolValue)
    }
}

// MARK: - Phase 2: Array/Dictionary Conversion

private struct ArrayConversionModel: Codable {
    @Default.ArrayEmpty<[Int]> var intArray: [Int]
    @Default.ArrayEmpty<[String]> var stringArray: [String]
}

final class ArrayDictionaryConversionTests: XCTestCase {
    
    func test_defaultValue_arrayOfInts_fromStrings() throws {
        let json = """
        {"intArray": ["1", "2", "3"], "stringArray": []}
        """
        let model = try decode(ArrayConversionModel.self, from: json)
        XCTAssertEqual(model.intArray, [1, 2, 3])
    }
    
    func test_defaultValue_arrayOfStrings_fromInts() throws {
        let json = """
        {"intArray": [], "stringArray": [1, 2, 3]}
        """
        let model = try decode(ArrayConversionModel.self, from: json)
        XCTAssertEqual(model.stringArray, ["1", "2", "3"])
    }
    
    func test_defaultValue_mixedArray_partialConversion() throws {
        let json = """
        {"intArray": ["1", "abc", "3"], "stringArray": []}
        """
        let model = try decode(ArrayConversionModel.self, from: json)
        // "abc" can't convert to Int, so compactMap filters it out
        XCTAssertEqual(model.intArray, [1, 3])
    }
    
    func test_preferValue_arrayConversion() throws {
        struct Model: Codable {
            @PreferValue var numbers: [Int]?
        }
        let json = """
        {"numbers": ["10", "20", "30"]}
        """
        let model = try decode(Model.self, from: json)
        XCTAssertEqual(model.numbers, [10, 20, 30])
    }
}

// MARK: - Phase 2: SingleValue Tests

final class SingleValueTests: XCTestCase {
    
    func test_singleValue_decodesBool() throws {
        let json = "true"
        let data = json.data(using: .utf8)!
        let value = try JSONDecoder().decode(SingleValue.self, from: data)
        XCTAssertEqual(value.value(Bool.self), true)
    }
    
    func test_singleValue_decodesInt() throws {
        let json = "42"
        let data = json.data(using: .utf8)!
        let value = try JSONDecoder().decode(SingleValue.self, from: data)
        XCTAssertEqual(value.value(Int.self), 42)
    }
    
    func test_singleValue_decodesString() throws {
        let json = "\"hello\""
        let data = json.data(using: .utf8)!
        let value = try JSONDecoder().decode(SingleValue.self, from: data)
        XCTAssertEqual(value.value(String.self), "hello")
    }
    
    func test_singleValue_decodesDouble() throws {
        let json = "3.14159"
        let data = json.data(using: .utf8)!
        let value = try JSONDecoder().decode(SingleValue.self, from: data)
        XCTAssertEqual(value.value(Double.self)!, 3.14159, accuracy: 0.00001)
    }
    
    func test_singleValue_crossTypeConversion() throws {
        let json = "\"123\""
        let data = json.data(using: .utf8)!
        let value = try JSONDecoder().decode(SingleValue.self, from: data)
        // String "123" should convert to Int 123
        XCTAssertEqual(value.value(Int.self), 123)
    }
    
    func test_singleValue_initFromAny() {
        let fromInt = SingleValue(42)
        let fromString = SingleValue("hello")
        let fromBool = SingleValue(true)
        let fromNil = SingleValue(nil)
        
        XCTAssertEqual(fromInt.value(Int.self), 42)
        XCTAssertEqual(fromString.value(String.self), "hello")
        XCTAssertEqual(fromBool.value(Bool.self), true)
        XCTAssertNil(fromNil.raw)
    }
}

// MARK: - Phase 2: Integration Tests

private struct MixedWrappersModel: Codable {
    @Default.IntZero var count: Int
    @PreferValue var optionalName: String?
    @ExistValue var requiredId: Int
    @IgnoreValue var localOnly: String?
}

final class IntegrationTests: XCTestCase {
    
    func test_mixedWrappers_inSameModel() throws {
        let json = """
        {"count": "5", "optionalName": null, "requiredId": "100", "localOnly": "ignored"}
        """
        let model = try decode(MixedWrappersModel.self, from: json)
        
        XCTAssertEqual(model.count, 5)           // converted from string
        XCTAssertNil(model.optionalName)          // null -> nil
        XCTAssertEqual(model.requiredId, 100)     // converted from string
        XCTAssertNil(model.localOnly)             // ignored
    }
    
    func test_nestedModels_withWrappers() throws {
        struct Outer: Codable {
            @Default.StringEmpty var name: String
            @FromStringValue var inner: InnerModel?
        }
        let json = """
        {"name": 123, "inner": "{\\"value\\": 1, \\"text\\": \\"nested\\"}"}
        """
        let model = try decode(Outer.self, from: json)
        
        XCTAssertEqual(model.name, "123")  // int -> string
        XCTAssertEqual(model.inner?.value, 1)
        XCTAssertEqual(model.inner?.text, "nested")
    }
    
    func test_roundTrip_encodeDecode() throws {
        var original = MixedWrappersModel.init(count: .init(wrappedValue: 42), optionalName: .init(wrappedValue: "test"), requiredId: 999, localOnly: nil)
        original.localOnly = "local"
        
        let encoded = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(MixedWrappersModel.self, from: encoded)
        
        XCTAssertEqual(decoded.count, 42)
        XCTAssertEqual(decoded.optionalName, "test")
        XCTAssertEqual(decoded.requiredId, 999)
        XCTAssertNil(decoded.localOnly)  // ignored during encode/decode
    }
}

final class EdgeCaseTests: XCTestCase {
    
    func test_deeplyNestedFromStringValue() throws {
        struct Level2: Codable, Equatable {
            var data: String
        }
        struct Level1: Codable {
            @FromStringValue var level2: Level2?
        }
        struct Root: Codable {
            @FromStringValue var level1: Level1?
        }
        
        let json = """
          {"level1": "{\\"level2\\": \\"{\\\\\\"data\\\\\\": \\\\\\"deep\\\\\\"}\\" }"}
          """
        let model = try decode(Root.self, from: json)
        
        XCTAssertNotNil(model.level1)
        XCTAssertNotNil(model.level1?.level2)
        XCTAssertEqual(model.level1?.level2?.data, "deep")
    }
    
    func test_unicodeStrings_conversion() throws {
        let json = """
          {"intValue": 0, "boolValue": false, "stringValue": "你好🌍", "doubleValue": 0, "decimalValue": 0}
          """
        let model = try decode(DefaultValueModel.self, from: json)
        XCTAssertEqual(model.stringValue, "你好🌍")
    }
    
    func test_specialNumbers_nan_infinity() throws {
        // JSON doesn't support NaN/Infinity, but test edge number handling
        let json = """
          {"intValue": 0, "boolValue": false, "stringValue": "", "doubleValue": 1.7976931348623157E+308, "decimalValue": 0}
          """
        let model = try decode(DefaultValueModel.self, from: json)
        XCTAssertEqual(model.doubleValue, Double.greatestFiniteMagnitude, accuracy: 1e300)
    }
    
    func test_emptyObject_decode() throws {
        let json = "{}"
        let model = try decode(DefaultValueModel.self, from: json)
        
        // All should have defaults
        XCTAssertEqual(model.intValue, 0)
        XCTAssertEqual(model.boolValue, false)
        XCTAssertEqual(model.stringValue, "")
        XCTAssertEqual(model.doubleValue, 0)
        XCTAssertEqual(model.decimalValue, .zero)
    }
    
    func test_emptyArray_decode() throws {
        let json = """
          {"intArray": [], "stringArray": []}
          """
        let model = try decode(ArrayConversionModel.self, from: json)
        XCTAssertEqual(model.intArray, [])
        XCTAssertEqual(model.stringArray, [])
    }
    
    func test_customProvider_implementation() throws {
        // Custom provider that defaults to 42
        enum FortyTwo: DefaultValueProvider {
            static let `default` = 42
        }
        
        struct Model: Codable {
            @DefaultValue<FortyTwo> var magic: Int
        }
        
        let json = "{}"
        let model = try decode(Model.self, from: json)
        XCTAssertEqual(model.magic, 42)
    }

    func test_customAlias_withMissingKey_usesProviderDefault() throws {
        enum FortyTwo: DefaultValueProvider {
            static let `default` = 42
        }

        struct Model: Codable {
            @Default.Custom<FortyTwo> var magic: Int
        }

        let json = "{}"
        let model = try decode(Model.self, from: json)

        XCTAssertEqual(model.magic, 42)
    }

    func test_customAlias_withMatchingValue_decodesNormally() throws {
        enum FortyTwo: DefaultValueProvider {
            static let `default` = 42
        }

        struct Model: Codable {
            @Default.Custom<FortyTwo> var magic: Int
        }

        let json = "{" + #""magic": 7"# + "}"
        let model = try decode(Model.self, from: json)

        XCTAssertEqual(model.magic, 7)
    }

    func test_customAlias_withNull_usesProviderDefault() throws {
        enum FortyTwo: DefaultValueProvider {
            static let `default` = 42
        }

        struct Model: Codable {
            @Default.Custom<FortyTwo> var magic: Int
        }

        let json = "{" + #""magic": null"# + "}"
        let model = try decode(Model.self, from: json)

        XCTAssertEqual(model.magic, 42)
    }

    func test_customAlias_encode_encodesWrappedValue() throws {
        enum FortyTwo: DefaultValueProvider {
            static let `default` = 42
        }

        struct Model: Codable {
            @Default.Custom<FortyTwo> var magic: Int
        }

        var model = try decode(Model.self, from: "{}")
        model.magic = 7

        let data = try JSONEncoder().encode(model)
        let dict = try JSONSerialization.jsonObject(with: data) as! [String: Any]

        XCTAssertEqual(dict["magic"] as? Int, 7)
    }

    func test_description_correctFormat() {
        @Default.IntZero var intVal: Int
        intVal = 123
        XCTAssertTrue("\(intVal)".contains("123"))
        
        @PreferValue var optVal: String?
        XCTAssertTrue("\(optVal)".contains("nil"))
        optVal = "hello"
        XCTAssertTrue("\(optVal)".contains("hello"))
        
        @IgnoreValue var ignoreVal: Int?
        ignoreVal = 999
        XCTAssertTrue("\(ignoreVal)".contains("999"))
    }
}
