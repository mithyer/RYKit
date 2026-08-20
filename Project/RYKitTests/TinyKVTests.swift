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

    private func makeEncryptor(seed: UInt8) throws -> TinyKVAESGCMEncryptor {
        try TinyKVAESGCMEncryptor(keyData: Data(repeating: seed, count: 32))
    }

    private func makeEncryptedKV(dbName: String, tableName: String = "records", seed: UInt8 = 0xA1) throws -> TinyKV {
        let encryptor = try makeEncryptor(seed: seed)
        return TinyKV(
            dbName: dbName,
            tableName: tableName,
            config: TinyKV.Config(valueEncryptor: encryptor)
        )
    }

    /// Verifies `nil` encryption configuration preserves the existing raw-data behavior.
    // TEST:TinyKV.Config[test_configNil_keepsPlaintextBehavior]
    func test_configNil_keepsPlaintextBehavior() async throws {
        let dbName = "tinykv-plain-\(UUID().uuidString)"
        let key: TinyKVKey = .string("plain")
        let expected = Data("plain-value".utf8)
        let writer = TinyKV(dbName: dbName, tableName: "records", config: .init(valueEncryptor: nil))

        try await writer.set(data: expected, for: key)

        let reader = TinyKV(dbName: dbName, tableName: "records")
        let actual = try await reader.getData(for: key)
        XCTAssertEqual(actual, expected)
    }

    /// Verifies configured AES-GCM encryptors transparently round-trip values and hide the stored BLOB.
    // TEST:TinyKV[test_encryptedValue_roundTrips]
    func test_encryptedValue_roundTrips() async throws {
        let dbName = "tinykv-encrypted-\(UUID().uuidString)"
        let kv = try makeEncryptedKV(dbName: dbName)
        let expected = SampleValue(id: 10, name: "encrypted")
        let key: TinyKVKey = .string("encrypted-key")

        try await kv.set(value: expected, for: key)
        let actual: SampleValue = try await kv.getValue(for: key)
        XCTAssertEqual(actual, expected)

        let rawReader = TinyKV(dbName: dbName, tableName: "records")
        let stored = try await rawReader.getData(for: key)
        XCTAssertNotEqual(stored, try JSONEncoder().encode(expected))
    }

    /// Encryptor test double that forces TinyKV's encryption error mapping path.
    private struct FailingEncryptor: TinyKVValueEncryptor {
        /// Error intentionally raised by both encryptor operations.
        private enum Failure: Error {
            case expected
        }

        /// Always fails instead of returning encrypted data.
        /// - Parameters:
        ///   - data: Ignored plaintext bytes.
        ///   - associatedData: Ignored record identity bytes.
        /// - Returns: Never returns because the operation always throws.
        func encrypt(_ data: Data, associatedData: Data) throws -> Data {
            throw Failure.expected
        }

        /// Always fails instead of opening encrypted data.
        /// - Parameters:
        ///   - data: Ignored encrypted bytes.
        ///   - associatedData: Ignored record identity bytes.
        /// - Returns: Never returns because the operation always throws.
        func decrypt(_ data: Data, associatedData: Data) throws -> Data {
            throw Failure.expected
        }
    }

    /// Verifies a different AES-GCM key cannot open an existing value.
    // TEST:TinyKV[test_wrongKey_failsDecryption]
    func test_wrongKey_failsDecryption() async throws {
        let dbName = "tinykv-wrong-key-\(UUID().uuidString)"
        let writer = try makeEncryptedKV(dbName: dbName, seed: 0xB1)
        let reader = try makeEncryptedKV(dbName: dbName, seed: 0xB2)
        let key: TinyKVKey = .string("wrong-key")

        try await writer.set(data: Data("secret".utf8), for: key)

        do {
            _ = try await reader.getData(for: key)
            XCTFail("Expected decryption to fail with a different key")
        } catch let error as TinyKV.TinyKVError {
            XCTAssertEqual(error, .decryptionFailed)
        }
    }

    /// Verifies encryptor failures map to TinyKV's public encryption error.
    // TEST:TinyKVTests[test_encryptionFailure_mapsToTinyKVError]
    func test_encryptionFailure_mapsToTinyKVError() async throws {
        let dbName = "tinykv-encryption-failure-\(UUID().uuidString)"
        let kv = TinyKV(
            dbName: dbName,
            tableName: "records",
            config: TinyKV.Config(valueEncryptor: FailingEncryptor())
        )

        do {
            try await kv.set(data: Data("secret".utf8), for: .string("failing-encryptor"))
            XCTFail("Expected the failing encryptor to reject persistence")
        } catch {
            XCTAssertEqual(error as? TinyKV.TinyKVError, .encryptionFailed)
        }
    }

    func test_tamperedValue_failsDecryption() async throws {
        let dbName = "tinykv-tampered-\(UUID().uuidString)"
        let encrypted = try makeEncryptedKV(dbName: dbName)
        let raw = TinyKV(dbName: dbName, tableName: "records")
        let key: TinyKVKey = .int(7)

        try await encrypted.set(data: Data("secret".utf8), for: key)
        var tampered = try await raw.getData(for: key)
        tampered[tampered.count - 1] ^= 0x01
        try await raw.set(data: tampered, for: key)

        do {
            _ = try await encrypted.getData(for: key)
            XCTFail("Expected decryption to fail for tampered data")
        } catch let error as TinyKV.TinyKVError {
            XCTAssertEqual(error, .decryptionFailed)
        }
    }

    /// Verifies an unknown persisted envelope version maps to the public format error.
    // TEST:TinyKVTests[test_unsupportedEnvelopeVersion_failsWithUnsupportedEncryptionFormat]
    func test_unsupportedEnvelopeVersion_failsWithUnsupportedEncryptionFormat() async throws {
        let dbName = "tinykv-unsupported-version-\(UUID().uuidString)"
        let encrypted = try makeEncryptedKV(dbName: dbName)
        let raw = TinyKV(dbName: dbName, tableName: "records")
        let key: TinyKVKey = .string("unsupported-version")

        try await encrypted.set(data: Data("secret".utf8), for: key)
        var stored = try await raw.getData(for: key)
        guard stored.count > 5 else {
            XCTFail("Expected a versioned encrypted envelope")
            return
        }
        stored[4] = 0x02
        try await raw.set(data: stored, for: key)

        do {
            _ = try await encrypted.getData(for: key)
            XCTFail("Expected an unsupported encryption format error")
        } catch {
            XCTAssertEqual(error as? TinyKV.TinyKVError, .unsupportedEncryptionFormat)
        }
    }

    /// Verifies an encrypted store rejects persisted plaintext without a legacy fallback.
    // TEST:TinyKVTests[test_encryptedStore_rejectsLegacyPlaintextRecord]
    func test_encryptedStore_rejectsLegacyPlaintextRecord() async throws {
        let dbName = "tinykv-legacy-plaintext-\(UUID().uuidString)"
        let encrypted = try makeEncryptedKV(dbName: dbName)
        let raw = TinyKV(dbName: dbName, tableName: "records")
        let key: TinyKVKey = .string("legacy-plaintext")

        try await raw.set(data: Data("legacy-plaintext".utf8), for: key)

        do {
            _ = try await encrypted.getData(for: key)
            XCTFail("Expected encrypted storage to reject plaintext data")
        } catch {
            XCTAssertEqual(error as? TinyKV.TinyKVError, .decryptionFailed)
        }
    }

    /// Verifies ciphertext is bound to both the key value and its key type.
    // TEST:TinyKVTests[test_encryptedValueBoundToRecordIdentity_blobSwapFails]
    func test_encryptedValueBoundToRecordIdentity_blobSwapFails() async throws {
        let dbName = "tinykv-record-identity-\(UUID().uuidString)"
        let encrypted = try makeEncryptedKV(dbName: dbName)
        let raw = TinyKV(dbName: dbName, tableName: "records")
        let sourceKey: TinyKVKey = .string("source")
        let targetKeys: [TinyKVKey] = [.string("target"), .int(7)]
        let plaintext = Data("identity-bound-secret".utf8)

        try await encrypted.set(data: plaintext, for: sourceKey)
        let sourceCiphertext = try await raw.getData(for: sourceKey)
        for targetKey in targetKeys {
            try await raw.set(data: sourceCiphertext, for: targetKey)
        }

        let actualSource = try await encrypted.getData(for: sourceKey)
        XCTAssertEqual(actualSource, plaintext)
        for targetKey in targetKeys {
            do {
                _ = try await encrypted.getData(for: targetKey)
                XCTFail("Expected ciphertext copied to \(targetKey) to fail authentication")
            } catch {
                XCTAssertEqual(error as? TinyKV.TinyKVError, .decryptionFailed)
            }
        }
    }

    /// Verifies all key-based range selectors still work when only values are encrypted.
    // TEST:TinyKV[test_encryptedRangeQueries_preserveTinyKVQueryKeyBehavior]
    func test_encryptedRangeQueries_preserveTinyKVQueryKeyBehavior() async throws {
        let kv = try makeEncryptedKV(dbName: "tinykv-encrypted-range-\(UUID().uuidString)")

        try await kv.set(value: SampleValue(id: 1, name: "string-1"), for: .string("ab-1"))
        try await kv.set(value: SampleValue(id: 2, name: "string-2"), for: .string("ab-2"))
        try await kv.set(value: SampleValue(id: 3, name: "string-3"), for: .string("zz-3"))
        try await kv.set(value: SampleValue(id: 10, name: "int-10"), for: .int(10))
        try await kv.set(value: SampleValue(id: 20, name: "int-20"), for: .int(20))
        try await kv.set(value: SampleValue(id: 30, name: "int-30"), for: .int(30))

        let likeValues: [SampleValue] = try await kv.getValues(for: .string(like: "ab-%"), acend: true)
        let stringInValues: [SampleValue] = try await kv.getValues(for: .strings(in: ["zz-3", "ab-1"]), acend: true)
        let intRangeValues: [SampleValue] = try await kv.getValues(
            for: .int(condition: "$ >= 15 AND $ <= 30"),
            acend: false
        )
        let intInValues: [SampleValue] = try await kv.getValues(for: .ints(in: [30, 10]), acend: true)

        XCTAssertEqual(likeValues.map(\.id), [1, 2])
        XCTAssertEqual(stringInValues.map(\.id), [1, 3])
        XCTAssertEqual(intRangeValues.map(\.id), [30, 20])
        XCTAssertEqual(intInValues.map(\.id), [10, 30])
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

    func test_getValues_withIntConditionOr_returnsMatches() async throws {
        let kv = makeKV()

        try await kv.set(value: SampleValue(id: 1, name: "n1"), for: .int(1))
        try await kv.set(value: SampleValue(id: 2, name: "n2"), for: .int(2))
        try await kv.set(value: SampleValue(id: 3, name: "n3"), for: .int(3))

        let values: [SampleValue] = try await kv.getValues(for: .int(condition: "$ = 1 OR $ = 2"), acend: true)
        XCTAssertEqual(values.map(\.id), [1, 2])
    }

    func test_getValues_withIntConditionOrAndParentheses_respectsGrouping() async throws {
        let kv = makeKV()

        try await kv.set(value: SampleValue(id: 1, name: "n1"), for: .int(1))
        try await kv.set(value: SampleValue(id: 2, name: "n2"), for: .int(2))
        try await kv.set(value: SampleValue(id: 3, name: "n3"), for: .int(3))

        let values: [SampleValue] = try await kv.getValues(
            for: .int(condition: "$ = 1 OR ($ = 2 AND $ >= 2)"),
            acend: true
        )
        XCTAssertEqual(values.map(\.id), [1, 2])
    }

    func test_remove_withIntConditionOr_removesMatches() async throws {
        let kv = makeKV()

        try await kv.set(value: SampleValue(id: 1, name: "n1"), for: .int(1))
        try await kv.set(value: SampleValue(id: 2, name: "n2"), for: .int(2))
        try await kv.set(value: SampleValue(id: 3, name: "n3"), for: .int(3))

        try await kv.remove(for: .int(condition: "$ = 1 OR $ = 2"))

        let values: [SampleValue] = try await kv.getValues(for: .int(condition: "$ >= 0"), acend: true)
        XCTAssertEqual(values.map(\.id), [3])
    }

    func test_invalidIntConditionExpression_throwsOnQueryAndDelete() async throws {
        let kv = makeKV()
        try await kv.set(value: SampleValue(id: 1, name: "safe"), for: .int(1))

        let invalidCases: [(String, String)] = [
            ("", "empty expression"),
            ("$ >= 0 OR 1=1", "boolean bypass injection"),
            ("($ >= 0) OR (1=1)", "boolean bypass injection with parentheses"),
            ("$ >= 0; DROP TABLE records", "semicolon injection"),
            ("$ >= 0 -- comment", "line comment token"),
            ("$ >= 0 /* comment */", "block comment token")
        ]

        for (condition, label) in invalidCases {
            do {
                let _: [SampleValue] = try await kv.getValues(for: .int(condition: condition), acend: true)
                XCTFail("Expected TinyKVError.invalidRangeExpression for query case: \(label)")
            } catch let error as TinyKV.TinyKVError {
                XCTAssertEqual(error, .invalidRangeExpression, label)
            } catch {
                XCTFail("Unexpected error in query case \(label): \(error)")
            }

            do {
                try await kv.remove(for: .int(condition: condition))
                XCTFail("Expected TinyKVError.invalidRangeExpression for delete case: \(label)")
            } catch let error as TinyKV.TinyKVError {
                XCTAssertEqual(error, .invalidRangeExpression, label)
            } catch {
                XCTFail("Unexpected error in delete case \(label): \(error)")
            }
        }
    }


    func test_validIntConditionExpression_throwsOnQueryAndDelete() async throws {
        let queryKV = makeKV()
        try await queryKV.set(value: SampleValue(id: 1, name: "n1"), for: .int(1))
        try await queryKV.set(value: SampleValue(id: 2, name: "n2"), for: .int(2))
        try await queryKV.set(value: SampleValue(id: 3, name: "n3"), for: .int(3))

        let validCases = [
            "$ >= 1",
            "$ = 1 OR $ = 2",
            "($ = 1) OR ($ = 2)",
            "$ >= 1 AND $ <= 3"
        ]

        for condition in validCases {
            let values: [SampleValue] = try await queryKV.getValues(for: .int(condition: condition), acend: true)
            XCTAssertFalse(values.isEmpty, "Expected non-empty query result for condition: \(condition)")
        }

        let deleteKV = makeKV()
        try await deleteKV.set(value: SampleValue(id: 1, name: "n1"), for: .int(1))
        try await deleteKV.set(value: SampleValue(id: 2, name: "n2"), for: .int(2))
        try await deleteKV.set(value: SampleValue(id: 3, name: "n3"), for: .int(3))

        try await deleteKV.remove(for: .int(condition: "$ = 1 OR $ = 2"))
        let remainValues: [SampleValue] = try await deleteKV.getValues(for: .int(condition: "$ >= 0"), acend: true)
        XCTAssertEqual(remainValues.map(\.id), [3])
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

    func test_getValue_whenDecodeTypeMismatch_throwsDecodeFailed() async throws {
        let kv = makeKV()
        try await kv.set(value: SampleValue(id: 7, name: "type-mismatch"), for: .string("decode-mismatch"))

        do {
            let _: Int = try await kv.getValue(for: .string("decode-mismatch"))
            XCTFail("Expected TinyKVError.decodeFailed")
        } catch let error as TinyKV.TinyKVError {
            XCTAssertEqual(error, .decodeFailed)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func test_getValues_withStringIn_whenKeysEmpty_returnsEmpty() async throws {
        let kv = makeKV()
        try await kv.set(value: SampleValue(id: 1, name: "seed"), for: .string("k1"))

        let values: [SampleValue] = try await kv.getValues(for: .strings(in: []), acend: true)

        XCTAssertTrue(values.isEmpty)
    }

    func test_getValues_withIntIn_whenKeysEmpty_returnsEmpty() async throws {
        let kv = makeKV()
        try await kv.set(value: SampleValue(id: 1, name: "seed"), for: .int(1))

        let values: [SampleValue] = try await kv.getValues(for: .ints(in: []), acend: true)

        XCTAssertTrue(values.isEmpty)
    }

    func test_getValues_withStringIn_whenKeysDuplicate_doesNotReturnDuplicates() async throws {
        let kv = makeKV()
        try await kv.set(value: SampleValue(id: 1, name: "k1"), for: .string("ab-1"))
        try await kv.set(value: SampleValue(id: 2, name: "k2"), for: .string("ab-2"))

        let values: [SampleValue] = try await kv.getValues(for: .strings(in: ["ab-1", "ab-1", "ab-2"]), acend: true)

        XCTAssertEqual(values.map(\.id), [1, 2])
        XCTAssertEqual(values.count, 2)
    }

    func test_getValues_withIntIn_whenKeysDuplicate_doesNotReturnDuplicates() async throws {
        let kv = makeKV()
        try await kv.set(value: SampleValue(id: 10, name: "n10"), for: .int(10))
        try await kv.set(value: SampleValue(id: 20, name: "n20"), for: .int(20))

        let values: [SampleValue] = try await kv.getValues(for: .ints(in: [20, 20, 10]), acend: true)

        XCTAssertEqual(values.map(\.id), [10, 20])
        XCTAssertEqual(values.count, 2)
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
