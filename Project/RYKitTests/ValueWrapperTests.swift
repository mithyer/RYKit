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

// MARK: - DefaultValue Tests

final class DefaultValueTests: XCTestCase {

    func test_decode_withMatchingType_succeeds() throws {
        let json = """
        {"intValue": 42, "boolValue": true, "stringValue": "hello", "doubleValue": 3.14, "decimalValue": 99.99}
        """
        let model = try decode(DefaultValueModel.self, from: json)

        XCTAssertEqual(model.intValue, 42)
        XCTAssertEqual(model.boolValue, true)
        XCTAssertEqual(model.stringValue, "hello")
        XCTAssertEqual(model.doubleValue, 3.14, accuracy: 0.001)
        XCTAssertEqual(model.decimalValue, Decimal(string: "99.99"))
    }

    func test_decode_withMissingKey_usesDefault() throws {
        let json = "{}"
        let model = try decode(DefaultValueModel.self, from: json)

        XCTAssertEqual(model.intValue, 0)
        XCTAssertEqual(model.boolValue, false)
        XCTAssertEqual(model.stringValue, "")
        XCTAssertEqual(model.doubleValue, 0)
        XCTAssertEqual(model.decimalValue, Decimal.zero)
    }

    func test_decode_withNullValue_usesDefault() throws {
        let json = """
        {"intValue": null, "boolValue": null, "stringValue": null, "doubleValue": null, "decimalValue": null}
        """
        let model = try decode(DefaultValueModel.self, from: json)

        XCTAssertEqual(model.intValue, 0)
        XCTAssertEqual(model.boolValue, false)
        XCTAssertEqual(model.stringValue, "")
        XCTAssertEqual(model.doubleValue, 0)
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

    func test_encode_outputsUnwrappedValue() throws {
        var model = DefaultValueModel()
        model.intValue = 100
        model.stringValue = "test"

        let data = try JSONEncoder().encode(model)
        let dict = try JSONSerialization.jsonObject(with: data) as! [String: Any]

        XCTAssertEqual(dict["intValue"] as? Int, 100)
        XCTAssertEqual(dict["stringValue"] as? String, "test")
    }

    func test_providers_boolFalse_default() {
        XCTAssertEqual(DefaultValueProviders.BoolFalse.default, false)
    }

    func test_providers_boolTrue_default() {
        XCTAssertEqual(DefaultValueProviders.BoolTrue.default, true)
    }

    func test_providers_intZero_default() {
        XCTAssertEqual(DefaultValueProviders.IntZero.default, 0)
    }

    func test_providers_stringEmpty_default() {
        XCTAssertEqual(DefaultValueProviders.StringEmpty.default, "")
    }

    func test_providers_arrayEmpty_default() throws {
        let json = "{}"
        let model = try decode(DefaultValueArrayModel.self, from: json)

        XCTAssertEqual(model.intArray, [])
        XCTAssertEqual(model.stringArray, [])
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

    func test_encode_preservesOriginalString() throws {
        let json = """
        {"inner": "{\\"value\\": 42, \\"text\\": \\"hello\\"}"}
        """
        let model = try decode(FromStringValueModel.self, from: json)

        let data = try JSONEncoder().encode(model)
        let jsonString = String(data: data, encoding: .utf8)!

        // Should encode as string (contains escaped quotes), not as nested object
        // String format: {"inner":"{\"value\": 42, ...}"}
        // Object format would be: {"inner":{"value":42,...}}
        XCTAssertTrue(jsonString.contains("\\\"value\\\""), "Should contain escaped quotes")
        XCTAssertFalse(jsonString.contains("\"inner\":{\"value\""), "Should not be a nested object")
    }
}

// MARK: - Helper

private func decode<T: Decodable>(_ type: T.Type, from json: String) throws -> T {
    let data = json.data(using: .utf8)!
    return try JSONDecoder().decode(T.self, from: data)
}
