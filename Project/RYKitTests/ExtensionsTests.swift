//
//  ExtensionsTests.swift
//  RYKitTests
//
//  Created by Claude on 2026/1/21.
//

import XCTest
import Combine
@testable import RYKit

// MARK: - Numeric Extension Tests

final class NumericExtensionTests: XCTestCase {

    func test_nilIfZero_int_zero_returnsNil() {
        let value: Int = 0
        XCTAssertNil(value.nilIfZero)
    }

    func test_nilIfZero_int_nonZero_returnsSelf() {
        let value: Int = 42
        XCTAssertEqual(value.nilIfZero, 42)
    }

    func test_nilIfZero_double_zero_returnsNil() {
        let value: Double = 0.0
        XCTAssertNil(value.nilIfZero)
    }

    func test_nilIfZero_double_nonZero_returnsSelf() {
        let value: Double = 3.14
        XCTAssertEqual(value.nilIfZero, 3.14)
    }

    func test_safeInt_finiteWholeNumber_returnsValue() {
        let value = Int(safe: 42.0)
        XCTAssertEqual(value, 42)
    }

    func test_safeInt_nan_returnsNil() {
        let value = Int(safe: Double.nan)
        XCTAssertNil(value)
    }

    func test_safeInt_positiveInfinity_returnsNil() {
        let value = Int(safe: Double.infinity)
        XCTAssertNil(value)
    }

    func test_safeInt_negativeInfinity_returnsNil() {
        let value = Int(safe: -Double.infinity)
        XCTAssertNil(value)
    }

    func test_safeInt_outOfRange_returnsNil() {
        let value = Int8(safe: 128.0)
        XCTAssertNil(value)
    }

    func test_safeInt_fractionalValue_nonStrict_truncates() {
        let value = Int(safe: 1.9)
        XCTAssertEqual(value, 1)
    }

    func test_safeInt_fractionalValue_strict_returnsNil() {
        let value = Int(safe: 1.9, strict: true)
        XCTAssertNil(value)
    }

    func test_safeInt_wholeNumber_strict_returnsValue() {
        let value = Int(safe: 42.0, strict: true)
        XCTAssertEqual(value, 42)
    }
}

// MARK: - Collection Extension Tests

final class CollectionExtensionTests: XCTestCase {
    
    func test_nilIfEmpty_array_empty_returnsNil() {
        let arr: [Int] = []
        XCTAssertNil(arr.nilIfEmpty)
    }
    
    func test_nilIfEmpty_array_nonEmpty_returnsSelf() {
        let arr = [1, 2, 3]
        XCTAssertEqual(arr.nilIfEmpty, [1, 2, 3])
    }
    
    func test_nilIfEmpty_string_empty_returnsNil() {
        let str = ""
        XCTAssertNil(str.nilIfEmpty)
    }
    
    func test_nilIfEmpty_string_nonEmpty_returnsSelf() {
        let str = "hello"
        XCTAssertEqual(str.nilIfEmpty, "hello")
    }
    
    func test_nilIfEmpty_dictionary_empty_returnsNil() {
        let dict: [String: Int] = [:]
        XCTAssertNil(dict.nilIfEmpty)
    }
}

// MARK: - String Subscript Tests

final class StringSubscriptTests: XCTestCase {
    
    func test_subscript_range_basic() {
        let str = "Hello World"
        let result: String = str[0..<5]
        XCTAssertEqual(result, "Hello")
    }
    
    func test_subscript_range_middle() {
        let str = "Hello World"
        let result: String = str[6..<11]
        XCTAssertEqual(result, "World")
    }
    
    func test_subscript_closedRange_basic() {
        let str = "Hello"
        let result: String = str[0...4]
        XCTAssertEqual(result, "Hello")
    }
    
    func test_subscript_range_outOfBounds_clamped() {
        let str = "Hi"
        let result: String = str[0..<100]
        XCTAssertEqual(result, "Hi")
    }
    
    func test_subscript_range_negative_clamped() {
        let str = "Hello"
        let result: String = str[-5..<3]
        XCTAssertEqual(result, "Hel")
    }
    
    func test_subscript_range_empty_returnsEmpty() {
        let str = "Hello"
        let result: String = str[5..<5]
        XCTAssertEqual(result, "")
    }
    
    func test_subscript_range_invalid_returnsEmpty() {
        let str = "Hello"
        let result: String = str[10..<20]
        XCTAssertEqual(result, "")
    }
}

// MARK: - SHA1 Tests

final class SHA1ExtensionTests: XCTestCase {
    
    func test_string_sha1() {
        let str = "hello"
        // Known SHA1 hash of "hello"
        XCTAssertEqual(str.sha1, "aaf4c61ddcc5e8a2dabede0f3b482cd9aea9434d")
    }
    
    func test_dictionary_sortedURLParams() {
        let dict: [String: String] = ["b": "2", "a": "1", "c": "3"]
        XCTAssertEqual(dict.sortedURLParams, "a=1&b=2&c=3")
    }
    
    func test_dictionary_sha1_consistent() {
        let dict1: [String: String] = ["b": "2", "a": "1"]
        let dict2: [String: String] = ["a": "1", "b": "2"]
        // Same content, different order should produce same SHA1
        XCTAssertEqual(dict1.sha1, dict2.sha1)
    }
    
    func test_array_sortedJoined() {
        let arr = ["c", "a", "b"]
        XCTAssertEqual(arr.sortedJoined(separator: ","), "a,b,c")
    }
}

// MARK: - Dictionary Type Conversion Tests
/*
 final class DictionaryConversionTests: XCTestCase {
 
 func test_subscript_withTypeConversion_stringToInt() {
 let dict: [String: Any] = ["count": "42"]
 let value: Int? = dict[("count", Int.self)]
 XCTAssertEqual(value, 42)
 }
 
 func test_subscript_withTypeConversion_intToString() {
 let dict: [String: Any] = ["name": 123]
 let value: String? = dict[("name", String.self)]
 XCTAssertEqual(value, "123")
 }
 
 func test_subscript_missingKey_returnsNil() {
 let dict: [String: Any] = ["a": 1]
 let value: Int? = dict[("b", Int.self)]
 XCTAssertNil(value)
 }
 
 func test_compactMapValuesByConvertingTo() {
 let dict: [String: Any] = ["a": "1", "b": "2", "c": "invalid"]
 let result = dict.compactMapValuesByConvertingTo(Int.self)
 XCTAssertEqual(result["a"], 1)
 XCTAssertEqual(result["b"], 2)
 XCTAssertNil(result["c"])
 }
 }
 
 // MARK: - Array Type Conversion Tests
 
 final class ArrayConversionTests: XCTestCase {
 
 func test_subscript_withTypeConversion() {
 let arr: [Any] = ["42", 100, "hello"]
 let value: Int? = arr[(0, Int.self)]
 XCTAssertEqual(value, 42)
 }
 
 func test_subscript_outOfBounds_returnsNil() {
 let arr: [Any] = [1, 2]
 let value: Int? = arr[(10, Int.self)]
 XCTAssertNil(value)
 }
 
 func test_compactMapByConvertingTo() {
 let arr: [Any] = ["1", "2", "abc", "3"]
 let result = arr.compactMapByConvertingTo(Int.self)
 XCTAssertEqual(result, [1, 2, 3])
 }
 }
 */
// MARK: - Decodable Extension Tests

final class DecodableExtensionTests: XCTestCase {
    
    struct Person: Codable, Equatable {
        var name: String
        var age: Int
    }
    
    func test_fromJsonString_valid() {
        let json = "{\"name\": \"Alice\", \"age\": 30}"
        let person = Person(fromJsonString: json)
        XCTAssertEqual(person, Person(name: "Alice", age: 30))
    }
    
    func test_fromJsonString_invalid_returnsNil() {
        let json = "invalid json"
        let person = Person(fromJsonString: json)
        XCTAssertNil(person)
    }
    
    func test_fromJsonDic_valid() {
        let dict: [String: Any] = ["name": "Bob", "age": 25]
        let person = Person(fromJsonDic: dict)
        XCTAssertEqual(person, Person(name: "Bob", age: 25))
    }
    
    func test_jsonString_roundTrip() {
        let person = Person(name: "Charlie", age: 35)
        let jsonString = person.jsonString
        XCTAssertNotNil(jsonString)
        
        let decoded = Person(fromJsonString: jsonString!)
        XCTAssertEqual(decoded, person)
    }
}

final class CombineStoreTests: XCTestCase {
    
    class TestHolder: Associatable {
        init() {}
    }
    
    func test_store_toObject_retainsCancellable() {
        let holder = TestHolder()
        let subject = PassthroughSubject<Int, Never>()
        var received: Int?
        
        subject
            .sink { received = $0 }
            .ry.store(to: holder, with: "test")
        
        subject.send(42)
        XCTAssertEqual(received, 42)
    }
    
    func test_store_toObject_withSameKey_doNotStore() {
        let holder = TestHolder()
        let subject = PassthroughSubject<Int, Never>()
        var count = 0
        
        subject
            .sink { _ in count += 1 }
            .ry.store(to: holder, with: "key1", doNotStoreIfHasSameKey: false)
        
        subject
            .sink { _ in count += 1 }
            .ry.store(to: holder, with: "key1", doNotStoreIfHasSameKey: true)
        
        subject.send(1)
        // Second subscription was skipped due to same key
        XCTAssertEqual(count, 1)
    }
    
    func test_removeCancellable_stopsSink() {
        let holder = TestHolder()
        let subject = PassthroughSubject<Int, Never>()
        var received: [Int] = []
        
        subject
            .sink { received.append($0) }
            .ry.store(to: holder, with: "removable")
        
        subject.send(1)
        holder.ry.cancelSubject(for: "removable")
        
        subject.send(2)
        XCTAssertEqual(received, [1])
    }
}

final class PublisherWaitOnceTests: XCTestCase {
    
    func test_waitOnce_receivesValue_beforeTimeout() {
        let subject = PassthroughSubject<Int, Never>()
        let expectation = expectation(description: "received")
        var result: Result<Int, TimeoutError>?
        
        let cancellable = subject.waitOnce(
            scheduler: DispatchQueue.main,
            timeout: .seconds(1)
        ) { res in
            result = res
            expectation.fulfill()
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            subject.send(42)
        }
        
        wait(for: [expectation], timeout: 2.0)
        XCTAssertEqual(result?.output, 42)
        XCTAssertFalse(result?.isTimeout ?? true)
        _ = cancellable
    }
    
    func test_waitOnce_timeout_whenNoValue() {
        let subject = PassthroughSubject<Int, Never>()
        let expectation = expectation(description: "timeout")
        var result: Result<Int, TimeoutError>?
        
        let cancellable = subject.waitOnce(
            scheduler: DispatchQueue.main,
            timeout: .milliseconds(100)
        ) { res in
            result = res
            expectation.fulfill()
        }
        
        wait(for: [expectation], timeout: 1.0)
        XCTAssertTrue(result?.isTimeout ?? false)
        XCTAssertNil(result?.output)
        _ = cancellable
    }
    
    func test_waitOnce_until_condition() {
        let subject = PassthroughSubject<Int, Never>()
        let expectation = expectation(description: "received")
        var result: Result<Int, TimeoutError>?
        
        let cancellable = subject.waitOnce(
            until: { $0 > 10 },
            scheduler: DispatchQueue.main,
            timeout: .seconds(1)
        ) { res in
            result = res
            expectation.fulfill()
        }
        
        subject.send(5)   // Ignored
        subject.send(8)   // Ignored
        subject.send(15)  // Matches
        
        wait(for: [expectation], timeout: 2.0)
        XCTAssertEqual(result?.output, 15)
        _ = cancellable
    }
    
    func test_waitOnce_forSpecificValue() {
        let subject = PassthroughSubject<String, Never>()
        let expectation = expectation(description: "received")
        var result: Result<String, TimeoutError>?
        
        let cancellable = subject.waitOnce(
            for: "target",
            scheduler: DispatchQueue.main,
            timeout: .seconds(1)
        ) { res in
            result = res
            expectation.fulfill()
        }
        
        subject.send("other")
        subject.send("target")
        
        wait(for: [expectation], timeout: 2.0)
        XCTAssertEqual(result?.output, "target")
        _ = cancellable
    }
    
    func test_timeoutError_result_helpers() {
        let success: Result<Int, TimeoutError> = .success(42)
        let failure: Result<Int, TimeoutError> = .failure(TimeoutError())
        
        XCTAssertFalse(success.isTimeout)
        XCTAssertEqual(success.output, 42)
        
        XCTAssertTrue(failure.isTimeout)
        XCTAssertNil(failure.output)
    }
    
    func test_dispatchTimeInterval_stride() {
        let seconds = DispatchTimeInterval.seconds(5)
        let millis = DispatchTimeInterval.milliseconds(500)
        
        XCTAssertEqual(seconds.stride, .seconds(5))
        XCTAssertEqual(millis.stride, .milliseconds(500))
    }
}
