//
//  TinyKVTests.swift
//  RYKitTests
//
//  Created by Codex on 2026/3/26.
//

import XCTest
@testable import RYKit

final class TinyKVTests: XCTestCase {

    private struct SampleValue: Codable, Equatable {
        let id: Int
        let name: String
    }

    private enum ConcurrentTestError: Error {
        case invalidValue
        case emptySnapshot
    }

    private func makeKV(tableName: String = "records") -> TinyKV {
        let dbName = "tinykv-tests-\(UUID().uuidString)"
        return TinyKV(dbName: dbName, tableName: tableName)
    }

    private func waitUntilReleased(
        _ object: @escaping () -> AnyObject?,
        timeout: TimeInterval = 1.5,
        pollIntervalNanoseconds: UInt64 = 10_000_000
    ) async -> Bool {
        let deadline = DispatchTime.now().uptimeNanoseconds + UInt64(timeout * 1_000_000_000)
        while DispatchTime.now().uptimeNanoseconds < deadline {
            if object() == nil {
                return true
            }
            try? await Task.sleep(nanoseconds: pollIntervalNanoseconds)
        }
        return object() == nil
    }

    func test_setAndGetValue_withStringKey_roundTripsCodable() async throws {
        let kv = makeKV()
        let expected = SampleValue(id: 1, name: "alpha")

        try await kv.set(value: expected, for: .string("user:1"))
        let actual: SampleValue = try await kv.getValue(for: .string("user:1"))

        XCTAssertEqual(actual, expected)
    }

    func test_setAndGetData_withIntKey_returnsEncodedBlob() async throws {
        let kv = makeKV()
        let expected = SampleValue(id: 2, name: "beta")

        try await kv.set(value: expected, for: .int(20))
        let data = try await kv.getData(for: .int(20))
        let decoded = try JSONDecoder().decode(SampleValue.self, from: data)

        XCTAssertEqual(decoded, expected)
    }

    func test_setDataAndGetData_withStringKey_roundTripsRawBlob() async throws {
        let kv = makeKV()
        let expected = SampleValue(id: 3, name: "raw")
        let raw = try JSONEncoder().encode(expected)

        try await kv.set(data: raw, for: .string("raw-key"))
        let data = try await kv.getData(for: .string("raw-key"))
        let decoded = try JSONDecoder().decode(SampleValue.self, from: data)

        XCTAssertEqual(decoded, expected)
    }

    func test_getValues_withStringLike_returnsAscendingAndDescending() async throws {
        let kv = makeKV()

        try await kv.set(value: SampleValue(id: 1, name: "k1"), for: .string("ab-1"))
        try await kv.set(value: SampleValue(id: 2, name: "k2"), for: .string("ab-2"))
        try await kv.set(value: SampleValue(id: 3, name: "k3"), for: .string("zz-3"))

        let asc: [SampleValue] = try await kv.getValues(for: .string(like: "ab-%"), acend: true)
        let desc: [SampleValue] = try await kv.getValues(for: .string(like: "ab-%"), acend: false)

        XCTAssertEqual(asc.map(\.id), [1, 2])
        XCTAssertEqual(desc.map(\.id), [2, 1])
    }

    func test_getValues_withStringIn_returnsAscendingAndDescending() async throws {
        let kv = makeKV()

        try await kv.set(value: SampleValue(id: 1, name: "k1"), for: .string("ab-1"))
        try await kv.set(value: SampleValue(id: 2, name: "k2"), for: .string("ab-2"))
        try await kv.set(value: SampleValue(id: 3, name: "k3"), for: .string("zz-3"))

        let asc: [SampleValue] = try await kv.getValues(for: .strings(in: ["zz-3", "ab-1"]), acend: true)
        let desc: [SampleValue] = try await kv.getValues(for: .strings(in: ["zz-3", "ab-1"]), acend: false)

        XCTAssertEqual(asc.map(\.id), [1, 3])
        XCTAssertEqual(desc.map(\.id), [3, 1])
    }

    func test_getValues_withIntRange_returnsAscendingAndDescending() async throws {
        let kv = makeKV()

        try await kv.set(value: SampleValue(id: 10, name: "n10"), for: .int(10))
        try await kv.set(value: SampleValue(id: 20, name: "n20"), for: .int(20))
        try await kv.set(value: SampleValue(id: 30, name: "n30"), for: .int(30))

        let asc: [SampleValue] = try await kv.getValues(for: .int(condition: "$ >= 15 AND $ <= 30"), acend: true)
        let desc: [SampleValue] = try await kv.getValues(for: .int(condition: "$ >= 15 AND $ <= 30"), acend: false)

        XCTAssertEqual(asc.map(\.id), [20, 30])
        XCTAssertEqual(desc.map(\.id), [30, 20])
    }

    func test_getValues_withIntIn_returnsAscendingAndDescending() async throws {
        let kv = makeKV()

        try await kv.set(value: SampleValue(id: 10, name: "n10"), for: .int(10))
        try await kv.set(value: SampleValue(id: 20, name: "n20"), for: .int(20))
        try await kv.set(value: SampleValue(id: 30, name: "n30"), for: .int(30))

        let asc: [SampleValue] = try await kv.getValues(for: .ints(in: [30, 10]), acend: true)
        let desc: [SampleValue] = try await kv.getValues(for: .ints(in: [30, 10]), acend: false)

        XCTAssertEqual(asc.map(\.id), [10, 30])
        XCTAssertEqual(desc.map(\.id), [30, 10])
    }

    func test_invalidIntConditionExpression_throwsOnQueryAndDelete() async throws {
        let kv = makeKV()
        try await kv.set(value: SampleValue(id: 1, name: "safe"), for: .int(1))

        do {
            let _: [SampleValue] = try await kv.getValues(for: .int(condition: "$ >= 0; DROP TABLE records; --"), acend: true)
            XCTFail("Expected TinyKVError.invalidRangeExpression")
        } catch let error as TinyKV.TinyKVError {
            XCTAssertEqual(error, .invalidRangeExpression)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }

        do {
            try await kv.remove(for: .int(condition: "$ >= 0 /* delete all */"))
            XCTFail("Expected TinyKVError.invalidRangeExpression")
        } catch let error as TinyKV.TinyKVError {
            XCTAssertEqual(error, .invalidRangeExpression)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func test_allKeys_includesEmptyStringKey() async throws {
        let kv = makeKV()

        try await kv.set(value: SampleValue(id: 99, name: "empty"), for: .string(""))

        let keys = try await kv.allKeys()
        let hasEmptyStringKey = keys.contains { key in
            if case .string("") = key {
                return true
            }
            return false
        }
        XCTAssertTrue(hasEmptyStringKey)
    }

    func test_getData_whenKeyMissing_throwsNotFound() async {
        let kv = makeKV()

        do {
            _ = try await kv.getData(for: .string("missing"))
            XCTFail("Expected TinyKVError.notFound")
        } catch let error as TinyKV.TinyKVError {
            XCTAssertEqual(error, .notFound)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func test_removeAll_clearsCountAndAllKeys() async throws {
        let kv = makeKV()

        try await kv.set(value: SampleValue(id: 1, name: "s"), for: .string("k1"))
        try await kv.set(value: SampleValue(id: 2, name: "i"), for: .int(2))

        let initialCount = try await kv.count()
        let initialKeys = try await kv.allKeys()
        let normalized = Set(initialKeys.map { key in
            switch key {
            case .string(let value): return "s:\(value)"
            case .int(let value): return "i:\(value)"
            }
        })

        XCTAssertEqual(initialCount, 2)
        XCTAssertEqual(normalized, Set(["s:k1", "i:2"]))

        try await kv.removeAll()

        let count = try await kv.count()
        let keys = try await kv.allKeys()
        XCTAssertEqual(count, 0)
        XCTAssertTrue(keys.isEmpty)
    }

    func test_extremeConcurrentWrites_withUniqueStringKeys_allValuesPersisted() async throws {
        let kv = makeKV()
        let total = 600

        try await withThrowingTaskGroup(of: Void.self) { group in
            for i in 0..<total {
                group.addTask {
                    try await kv.set(value: SampleValue(id: i, name: "name-\(i)"), for: .string("user-\(i)"))
                }
            }
            try await group.waitForAll()
        }

        let values: [SampleValue] = try await kv.getValues(for: .string(like: "user-%"), acend: true)
        XCTAssertEqual(values.count, total)
        XCTAssertEqual(Set(values.map(\.id)), Set(0..<total))
    }

    func test_extremeConcurrentReadWrite_onIntKeys_keepsRecordsDecodable() async throws {
        let kv = makeKV()
        let keyCount = 128
        let operations = 2_000

        for i in 0..<keyCount {
            try await kv.set(value: SampleValue(id: i, name: "seed-\(i)"), for: .int(i))
        }

        try await withThrowingTaskGroup(of: Void.self) { group in
            for i in 0..<operations {
                group.addTask {
                    let key = i % keyCount
                    if i % 3 == 0 {
                        try await kv.set(value: SampleValue(id: i, name: "write-\(i)"), for: .int(key))
                    } else {
                        let value: SampleValue = try await kv.getValue(for: .int(key))
                        guard !value.name.isEmpty else {
                            throw ConcurrentTestError.invalidValue
                        }
                    }
                }
            }
            try await group.waitForAll()
        }

        let finalValues: [SampleValue] = try await kv.getValues(for: .int(condition: "$ >= 0 AND $ < \(keyCount)"), acend: true)
        XCTAssertEqual(finalValues.count, keyCount)
    }

    func test_extremeConcurrentUpserts_onSameIntKey_valueRemainsValid() async throws {
        let kv = makeKV()
        let writes = 1_000
        let key: Int = 7

        try await withThrowingTaskGroup(of: Void.self) { group in
            for i in 0..<writes {
                group.addTask {
                    try await kv.set(value: SampleValue(id: i, name: "same-\(i)"), for: .int(key))
                }
            }
            try await group.waitForAll()
        }

        let value: SampleValue = try await kv.getValue(for: .int(key))
        XCTAssertTrue((0..<writes).contains(value.id))
        XCTAssertTrue(value.name.hasPrefix("same-"))
    }

    func test_extremeConcurrentRangeQueries_whileWriting_doNotThrow() async throws {
        let kv = makeKV()
        let keyCount = 256
        let operations = 800

        for i in 0..<keyCount {
            try await kv.set(value: SampleValue(id: i, name: "seed-int-\(i)"), for: .int(i))
            try await kv.set(value: SampleValue(id: i, name: "seed-str-\(i)"), for: .string("seed-\(i)"))
        }

        try await withThrowingTaskGroup(of: Void.self) { group in
            for i in 0..<operations {
                group.addTask {
                    let key = i % keyCount
                    if i % 4 == 0 {
                        try await kv.set(value: SampleValue(id: 10_000 + i, name: "mut-int-\(i)"), for: .int(key))
                    } else if i % 4 == 1 {
                        try await kv.set(value: SampleValue(id: 20_000 + i, name: "mut-str-\(i)"), for: .string("seed-\(Int(key))"))
                    } else if i % 4 == 2 {
                        let values: [SampleValue] = try await kv.getValues(
                            for: .int(condition: "$ >= 0 AND $ < \(keyCount)"),
                            acend: (i % 8 == 2)
                        )
                        guard !values.isEmpty else {
                            throw ConcurrentTestError.emptySnapshot
                        }
                    } else {
                        let values: [SampleValue] = try await kv.getValues(
                            for: .string(like: "seed-%"),
                            acend: (i % 8 == 3)
                        )
                        guard !values.isEmpty else {
                            throw ConcurrentTestError.emptySnapshot
                        }
                    }
                }
            }
            try await group.waitForAll()
        }

        let intValues: [SampleValue] = try await kv.getValues(for: .int(condition: "$ >= 0 AND $ < \(keyCount)"), acend: true)
        let strValues: [SampleValue] = try await kv.getValues(for: .string(like: "seed-%"), acend: true)
        XCTAssertEqual(intValues.count, keyCount)
        XCTAssertEqual(strValues.count, keyCount)
    }

    func test_deinit_afterBasicReadWrite_instanceReleased() async throws {
        weak var weakKV: TinyKV?

        do {
            let kv = makeKV()
            weakKV = kv

            try await kv.set(value: SampleValue(id: 100, name: "deinit-basic"), for: .string("deinit-basic"))
            let value: SampleValue = try await kv.getValue(for: .string("deinit-basic"))
            XCTAssertEqual(value.id, 100)
        }

        let released = await waitUntilReleased { weakKV }
        XCTAssertTrue(released, "TinyKV instance should be released after leaving scope")
        XCTAssertNil(weakKV)
    }

    func test_deinit_underStress_multipleCreateDestroy_noRetainedInstances() async throws {
        let rounds = 120

        for i in 0..<rounds {
            weak var weakKV: TinyKV?

            do {
                let kv = makeKV(tableName: "records_\(i)")
                weakKV = kv

                try await kv.set(value: SampleValue(id: i, name: "stress-\(i)"), for: .int(i))
                _ = try await kv.getData(for: .int(i))
            }

            let released = await waitUntilReleased { weakKV }
            XCTAssertTrue(released, "TinyKV instance leaked at round \(i)")
            XCTAssertNil(weakKV)
        }
    }
}
