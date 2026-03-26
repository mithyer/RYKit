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

    private func makeBufferedKV(dbName: String = UUID().uuidString, tableName: String = "buffered", bufferLimit: Int = 2) -> TinyBufferedKV {
        TinyBufferedKV(
            dbName: dbName,
            tableName: tableName,
            config: .init(bufferLimit: bufferLimit)
        )
    }

    private func makeTinyKV(dbName: String, tableName: String) -> TinyKV {
        TinyKV(dbName: dbName, tableName: tableName)
    }

    private func assertRawValueMissing(_ kv: TinyKV, key: TinyKV.Key) async throws {
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
        XCTExpectFailure("Pending Task 3/4")
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
        XCTExpectFailure("Pending Task 3/4")
        let dbName = randomDBName(prefix: "autoflush")
        let kv = TinyBufferedKV(dbName: dbName, tableName: "auto", config: .init(bufferLimit: 1))

        try await kv.set(value: SampleValue(value: "first"), for: .string("k1"))
        try await kv.set(value: SampleValue(value: "second"), for: .string("k2"))

        let persistedFirst: SampleValue = try await makeTinyKV(dbName: dbName, tableName: "auto").getValue(for: .string("k1"))
        let persistedSecond: SampleValue = try await makeTinyKV(dbName: dbName, tableName: "auto").getValue(for: .string("k2"))

        XCTAssertEqual(persistedFirst.value, "first")
        XCTAssertEqual(persistedSecond.value, "second")
    }

    func test_getValues_flushesBeforeRangeQuery() async throws {
        XCTExpectFailure("Pending Task 3/4")
        let dbName = randomDBName(prefix: "range-flush")
        let tableName = "range"
        let kv = TinyBufferedKV(dbName: dbName, tableName: tableName, config: .init(bufferLimit: 10))

        let rawKV = makeTinyKV(dbName: dbName, tableName: tableName)
        let pattern: TinyKV.RangeKey = .string(like: "range-%")

        try await kv.set(value: SampleValue(value: "pending"), for: .string("range-1"))
        let before: [SampleValue] = try await rawKV.getValues(for: pattern)
        XCTAssertTrue(before.isEmpty, "Expected no persisted rows before range query flush")

        let results: [SampleValue] = try await kv.getValues(for: .string(like: "range-%"))

        XCTAssertEqual(results, [SampleValue(value: "pending")])

        let persisted: [SampleValue] = try await rawKV.getValues(for: pattern)
        XCTAssertEqual(persisted, results)
    }
}
