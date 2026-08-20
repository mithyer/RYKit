//
//  TinyKVEncryptionTests.swift
//  RYKitTests
//
//  Created by Codex on 2026/8/20.
//

import CryptoKit
import Security
import XCTest
@testable import RYKit

final class TinyKVEncryptionTests: XCTestCase {

    /// Verifies AES-GCM round trips and produces a fresh ciphertext for each write.
    // TEST:TinyKVEncryptionTests[test_aesGCMEncryptor_roundTripsAndAuthenticates]
    func test_aesGCMEncryptor_roundTripsAndAuthenticates() throws {
        let encryptor = try TinyKVAESGCMEncryptor(
            keyData: Data(repeating: 0x11, count: 32)
        )
        let plaintext = Data("secret-value".utf8)
        let associatedData = Data("record-1".utf8)

        let first = try encryptor.encrypt(plaintext, associatedData: associatedData)
        let second = try encryptor.encrypt(plaintext, associatedData: associatedData)

        XCTAssertNotEqual(first, second)
        XCTAssertEqual(try encryptor.decrypt(first, associatedData: associatedData), plaintext)
    }

    /// Verifies AES-GCM rejects modified nonce, ciphertext, tag, and record identity.
    // TEST:TinyKVEncryptionTests[test_aesGCMEncryptor_rejectsTamperingAndWrongAssociatedData]
    func test_aesGCMEncryptor_rejectsTamperingAndWrongAssociatedData() throws {
        let encryptor = try TinyKVAESGCMEncryptor(
            keyData: Data(repeating: 0x22, count: 32)
        )
        let associatedData = Data("record-2".utf8)
        let validCiphertext = try encryptor.encrypt(Data("secret".utf8), associatedData: associatedData)

        // The envelope contains a 5-byte header followed by a 12-byte nonce, ciphertext, and tag.
        for index in [5, 17, validCiphertext.count - 1] {
            var tampered = validCiphertext
            tampered[index] ^= 0x01
            XCTAssertThrowsError(
                try encryptor.decrypt(tampered, associatedData: associatedData),
                "tampered byte at index \(index)"
            ) { error in
                XCTAssertEqual(error as? TinyKVEncryptionError, .decryptionFailed)
            }
        }

        XCTAssertThrowsError(
            try encryptor.decrypt(validCiphertext, associatedData: Data("record-3".utf8))
        ) { error in
            XCTAssertEqual(error as? TinyKVEncryptionError, .decryptionFailed)
        }
    }

    /// Verifies empty plaintext is preserved through AES-GCM encryption and decryption.
    // TEST:TinyKVEncryptionTests[test_aesGCMEncryptor_roundTripsEmptyPlaintext]
    func test_aesGCMEncryptor_roundTripsEmptyPlaintext() throws {
        let encryptor = try TinyKVAESGCMEncryptor(
            keyData: Data(repeating: 0x23, count: 32)
        )
        let associatedData = Data("empty-record".utf8)
        let ciphertext = try encryptor.encrypt(Data(), associatedData: associatedData)

        XCTAssertEqual(try encryptor.decrypt(ciphertext, associatedData: associatedData), Data())
    }

    /// Verifies the public RYKV envelope can be opened when assembled from a valid AES-GCM sealed box.
    // TEST:TinyKVEncryptionTests[test_aesGCMEncryptor_acceptsHandcraftedEnvelope]
    func test_aesGCMEncryptor_acceptsHandcraftedEnvelope() throws {
        let keyData = Data(repeating: 0x24, count: 32)
        let encryptor = try TinyKVAESGCMEncryptor(keyData: keyData)
        let plaintext = Data("handcrafted-envelope".utf8)
        let associatedData = Data("handcrafted-record".utf8)
        let sealedBox = try AES.GCM.seal(
            plaintext,
            using: SymmetricKey(data: keyData),
            authenticating: associatedData
        )
        guard let combined = sealedBox.combined else {
            XCTFail("Expected AES-GCM to produce a combined sealed box")
            return
        }
        let envelope = Data([0x52, 0x59, 0x4B, 0x56, 0x01]) + combined

        XCTAssertEqual(try encryptor.decrypt(envelope, associatedData: associatedData), plaintext)
    }

    /// Verifies malformed envelopes and unknown versions produce distinct format errors.
    // TEST:TinyKVEncryptionTests[test_aesGCMEncryptor_rejectsMalformedAndUnsupportedEnvelopes]
    func test_aesGCMEncryptor_rejectsMalformedAndUnsupportedEnvelopes() throws {
        let encryptor = try TinyKVAESGCMEncryptor(
            keyData: Data(repeating: 0x44, count: 32)
        )
        let envelopeMagic = Data([0x52, 0x59, 0x4B, 0x56])
        let associatedData = Data("record-format".utf8)
        let cases: [(String, Data, TinyKVEncryptionError)] = [
            ("empty envelope", Data(), .invalidEnvelope),
            ("header only", envelopeMagic + Data([0x01]), .invalidEnvelope),
            ("wrong magic", Data([0x00, 0x59, 0x4B, 0x56, 0x01, 0x00]), .invalidEnvelope),
            ("unsupported version", envelopeMagic + Data([0x02, 0x00]), .unsupportedEnvelopeVersion),
            (
                "truncated sealed box",
                envelopeMagic + Data([0x01]) + Data(repeating: 0x00, count: 27),
                .decryptionFailed
            )
        ]

        for (name, envelope, expectedError) in cases {
            XCTAssertThrowsError(
                try encryptor.decrypt(envelope, associatedData: associatedData),
                name
            ) { error in
                XCTAssertEqual(error as? TinyKVEncryptionError, expectedError, name)
            }
        }
    }

    /// Verifies an AES-GCM ciphertext cannot be opened with a different 256-bit key.
    // TEST:TinyKVEncryptionTests[test_aesGCMEncryptor_withDifferentKey_failsDecryption]
    func test_aesGCMEncryptor_withDifferentKey_failsDecryption() throws {
        let writer = try TinyKVAESGCMEncryptor(
            keyData: Data(repeating: 0x45, count: 32)
        )
        let reader = try TinyKVAESGCMEncryptor(
            keyData: Data(repeating: 0x46, count: 32)
        )
        let associatedData = Data("record-key".utf8)
        let ciphertext = try writer.encrypt(Data("secret".utf8), associatedData: associatedData)

        XCTAssertThrowsError(
            try reader.decrypt(ciphertext, associatedData: associatedData)
        ) { error in
            XCTAssertEqual(error as? TinyKVEncryptionError, .decryptionFailed)
        }
    }

    /// Verifies invalid AES key sizes are rejected before the encryptor is constructed.
    func test_aesGCMEncryptor_rejectsInvalidKeySize() {
        for byteCount in [16, 64] {
            XCTAssertThrowsError(
                try TinyKVAESGCMEncryptor(keyData: Data(repeating: 0x33, count: byteCount))
            ) { error in
                XCTAssertEqual(error as? TinyKVEncryptionError, .invalidKey, "key size: \(byteCount) bytes")
            }
        }
    }

    /// Verifies an empty Keychain service is rejected before any Keychain access.
    // TEST:TinyKVEncryptionTests[test_keychainEncryptor_rejectsEmptyService]
    func test_keychainEncryptor_rejectsEmptyService() {
        XCTAssertThrowsError(
            try TinyKVAESGCMEncryptor.loadOrCreateFromKeychain(service: "")
        ) { error in
            XCTAssertEqual(error as? TinyKVEncryptionError, .invalidKeychainService)
        }
    }

    /// Verifies an existing Keychain item with invalid key material is rejected.
    // TEST:TinyKVEncryptionTests[test_keychainEncryptor_rejectsExistingInvalidKey]
    func test_keychainEncryptor_rejectsExistingInvalidKey() {
        let service = "com.rykit.tests.tinykv.invalid-key.\(UUID().uuidString)"
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: "default"
        ]
        defer {
            SecItemDelete(query as CFDictionary)
        }

        let addQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: "default",
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
            kSecValueData as String: Data(repeating: 0x55, count: 16)
        ]
        XCTAssertEqual(SecItemAdd(addQuery as CFDictionary, nil), errSecSuccess)

        XCTAssertThrowsError(
            try TinyKVAESGCMEncryptor.loadOrCreateFromKeychain(service: service)
        ) { error in
            XCTAssertEqual(error as? TinyKVEncryptionError, .invalidKey)
        }
    }

    /// Verifies generated Keychain items use device-only accessibility while unlocked.
    // TEST:TinyKVEncryptionTests[test_keychainEncryptor_persistsWhenUnlockedAccessibility]
    func test_keychainEncryptor_persistsWhenUnlockedAccessibility() throws {
        let service = "com.rykit.tests.tinykv.accessibility.\(UUID().uuidString)"
        let cleanupQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: "default"
        ]
        defer {
            SecItemDelete(cleanupQuery as CFDictionary)
        }

        _ = try TinyKVAESGCMEncryptor.loadOrCreateFromKeychain(service: service)
        var result: CFTypeRef?
        let attributesQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: "default",
            kSecReturnAttributes as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        XCTAssertEqual(SecItemCopyMatching(attributesQuery as CFDictionary, &result), errSecSuccess)
        let attributes = result as? [String: Any]
        XCTAssertEqual(
            attributes?[kSecAttrAccessible as String] as? String,
            kSecAttrAccessibleWhenUnlockedThisDeviceOnly as String
        )
    }

    /// Verifies the Keychain factory reuses the same generated key for a stable service.
    // TEST:TinyKVEncryptionTests[test_keychainEncryptor_canLoadOrCreateKey]
    func test_keychainEncryptor_canLoadOrCreateKey() throws {
        let service = "com.rykit.tests.tinykv.\(UUID().uuidString)"
        defer {
            let query: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: service,
                kSecAttrAccount as String: "default"
            ]
            SecItemDelete(query as CFDictionary)
        }

        let first = try TinyKVAESGCMEncryptor.loadOrCreateFromKeychain(service: service)
        let second = try TinyKVAESGCMEncryptor.loadOrCreateFromKeychain(service: service)
        let plaintext = Data("keychain-value".utf8)
        let associatedData = Data("keychain-record".utf8)
        let ciphertext = try first.encrypt(plaintext, associatedData: associatedData)

        XCTAssertEqual(try second.decrypt(ciphertext, associatedData: associatedData), plaintext)
    }
}
