//
//  TinyBufferedKVTests.swift
//  RYKitTests
//
//  Created by Codex on 2026/3/26.
//

import XCTest
@testable import RYKit

@MainActor
final class TinyBufferedKVTests: XCTestCase {

    private struct SampleValue: Codable, Equatable {
        let value: String
    }

    private func randomDBName(prefix: String) -> String {
        "\(prefix)-\(UUID().uuidString)"
    }

    private func makeBufferedKV(
        dbName: String = UUID().uuidString,
        tableName: String = "buffered",
        config: TinyBufferedKV.Config = .init()
    ) -> TinyBufferedKV {
        TinyBufferedKV(dbName: dbName, tableName: tableName, config: config)
    }

    private func makeTinyKV(dbName: String, tableName: String) -> TinyKV {
        TinyKV(dbName: dbName, tableName: tableName)
    }

    private func assertRawValueMissing(_ kv: TinyKV, key: TinyKVKey) async throws {
        do {
            _ = try await kv.getData(for: key)
            XCTFail("Expected TinyKV not to contain a value for \(key) yet")
        } catch let error as TinyKV.TinyKVError {
            XCTAssertEqual(error, .notFound)
        }
    }

    func test_setThenGet_withoutFlush_readsFromBuffer() async throws {
        let dbName = randomDBName(prefix: "buffered")
        let tableName = "buffered"
        let kv = makeBufferedKV(dbName: dbName, tableName: tableName)
        let payload = SampleValue(value: "in-buffer")
        let rawKV = makeTinyKV(dbName: dbName, tableName: tableName)

        try await kv.set(value: payload, for: .string("buffered"))
        try await assertRawValueMissing(rawKV, key: .string("buffered"))

        let actual: SampleValue = try await kv.getValue(for: .string("buffered"))

        XCTAssertEqual(actual, payload)
    }

    func test_flush_persistsBufferedData_forNewInstance() async throws {
        let dbName = randomDBName(prefix: "flush")
        let writer = TinyBufferedKV(dbName: dbName, tableName: "shared", config: .init())
        let payload = SampleValue(value: "persisted")

        try await writer.set(value: payload, for: .string("shared-key"))
        try await writer.flush()

        let reader = TinyBufferedKV(dbName: dbName, tableName: "shared", config: .init())
        let actual: SampleValue = try await reader.getValue(for: .string("shared-key"))

        XCTAssertEqual(actual, payload)
    }

    func test_bufferLimitReached_triggersAutoFlush() async throws {
        let dbName = randomDBName(prefix: "autoflush")
        let config = TinyBufferedKV.Config(maxBufferedItems: 1, maxBufferedBytes: 1_048_576, flushInterval: 0)
        let kv = makeBufferedKV(dbName: dbName, tableName: "auto", config: config)

        try await kv.set(value: SampleValue(value: "first"), for: .string("k1"))
        try await kv.set(value: SampleValue(value: "second"), for: .string("k2"))

        let persistedFirst: SampleValue = try await makeTinyKV(dbName: dbName, tableName: "auto").getValue(for: .string("k1"))
        let persistedSecond: SampleValue = try await makeTinyKV(dbName: dbName, tableName: "auto").getValue(for: .string("k2"))

        XCTAssertEqual(persistedFirst.value, "first")
        XCTAssertEqual(persistedSecond.value, "second")
    }

    func test_bufferBytesLimitReached_triggersAutoFlush() async throws {
        let dbName = randomDBName(prefix: "autoflush-bytes")
        let config = TinyBufferedKV.Config(maxBufferedItems: 10, maxBufferedBytes: 128, flushInterval: 0)
        let kv = makeBufferedKV(dbName: dbName, tableName: "auto-bytes", config: config)

        let largeValue = SampleValue(value: String(repeating: "x", count: 90))
        let anotherLargeValue = SampleValue(value: String(repeating: "y", count: 90))

        try await kv.set(value: largeValue, for: .string("big-1"))
        try await kv.set(value: anotherLargeValue, for: .string("big-2"))

        let persistedFirst: SampleValue = try await makeTinyKV(dbName: dbName, tableName: "auto-bytes")
            .getValue(for: .string("big-1"))
        let persistedSecond: SampleValue = try await makeTinyKV(dbName: dbName, tableName: "auto-bytes")
            .getValue(for: .string("big-2"))

        XCTAssertEqual(persistedFirst, largeValue)
        XCTAssertEqual(persistedSecond, anotherLargeValue)
    }

    func test_getValues_flushesBeforeRangeQuery() async throws {
        let dbName = randomDBName(prefix: "range-flush")
        let tableName = "range"
        let config = TinyBufferedKV.Config(maxBufferedItems: 10, maxBufferedBytes: 1_048_576, flushInterval: 0)
        let kv = TinyBufferedKV(dbName: dbName, tableName: tableName, config: config)

        let rawKV = makeTinyKV(dbName: dbName, tableName: tableName)
        let pattern: TinyKVQueryKey = .string(like: "range-%")

        try await kv.set(value: SampleValue(value: "pending"), for: .string("range-1"))
        let before: [SampleValue] = try await rawKV.getValues(for: pattern)
        XCTAssertTrue(before.isEmpty, "Expected no persisted rows before range query flush")

        let results: [SampleValue] = try await kv.getValues(for: .string(like: "range-%"))

        XCTAssertEqual(results, [SampleValue(value: "pending")])

        let persisted: [SampleValue] = try await rawKV.getValues(for: pattern)
        XCTAssertEqual(persisted, results)
    }

    func test_concurrent_setFlushGet_hasNoLostUpdates() async throws {
        let dbName = randomDBName(prefix: "concurrent")
        let tableName = "concurrent"
        let config = TinyBufferedKV.Config(maxBufferedItems: 1_000, maxBufferedBytes: 10_000_000, flushInterval: 0)
        let kv = TinyBufferedKV(dbName: dbName, tableName: tableName, config: config)
        let total = 80

        try await withThrowingTaskGroup(of: Void.self) { group in
            for index in 0..<total {
                group.addTask {
                    try await kv.set(value: SampleValue(value: "v-\(index)"), for: .string("concurrent-\(index)"))
                }
            }

            group.addTask {
                for _ in 0..<20 {
                    try await kv.flush()
                }
            }

            try await group.waitForAll()
        }

        try await kv.flush()

        let persisted: [SampleValue] = try await makeTinyKV(dbName: dbName, tableName: tableName)
            .getValues(for: .string(like: "concurrent-%"))

        XCTAssertEqual(persisted.count, total)
        XCTAssertEqual(Set(persisted.map(\.value)).count, total)
    }

    func test_debounceFlush_onlyAfterInterval() async throws {
        let dbName = randomDBName(prefix: "debounce")
        let tableName = "debounce"
        let config = TinyBufferedKV.Config(maxBufferedItems: 100, maxBufferedBytes: 1_048_576, flushInterval: 0.2)
        let kv = TinyBufferedKV(dbName: dbName, tableName: tableName, config: config)
        let rawKV = makeTinyKV(dbName: dbName, tableName: tableName)

        try await kv.set(value: SampleValue(value: "v1"), for: .string("debounce-1"))

        try await assertRawValueMissing(rawKV, key: .string("debounce-1"))

        try await Task.sleep(nanoseconds: 350_000_000)

        let persisted: SampleValue = try await rawKV.getValue(for: .string("debounce-1"))
        XCTAssertEqual(persisted.value, "v1")
    }

    func test_debounceFlush_isResetBySubsequentSet() async throws {
        let dbName = randomDBName(prefix: "debounce-reset")
        let tableName = "debounce-reset"
        let config = TinyBufferedKV.Config(maxBufferedItems: 100, maxBufferedBytes: 1_048_576, flushInterval: 0.2)
        let kv = TinyBufferedKV(dbName: dbName, tableName: tableName, config: config)
        let rawKV = makeTinyKV(dbName: dbName, tableName: tableName)

        try await kv.set(value: SampleValue(value: "first"), for: .string("debounce-reset-1"))
        try await Task.sleep(nanoseconds: 120_000_000)
        try await kv.set(value: SampleValue(value: "second"), for: .string("debounce-reset-2"))

        try await Task.sleep(nanoseconds: 120_000_000)
        try await assertRawValueMissing(rawKV, key: .string("debounce-reset-1"))
        try await assertRawValueMissing(rawKV, key: .string("debounce-reset-2"))

        try await Task.sleep(nanoseconds: 180_000_000)

        let first: SampleValue = try await rawKV.getValue(for: .string("debounce-reset-1"))
        let second: SampleValue = try await rawKV.getValue(for: .string("debounce-reset-2"))
        XCTAssertEqual(first.value, "first")
        XCTAssertEqual(second.value, "second")
    }
}
