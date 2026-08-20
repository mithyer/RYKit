//
//  TinyKVEncryption.swift
//  RYKit
//
//  Created by Codex on 2026/8/20.
//

import CryptoKit
import Foundation
import Security

/// Errors produced while creating or using a TinyKV value encryptor.
public enum TinyKVEncryptionError: Error, Equatable {
    /// The supplied symmetric key is not 256 bits long.
    case invalidKey
    /// The Keychain service identifier is empty.
    case invalidKeychainService
    /// Reading the Keychain item failed.
    case keychainReadFailed
    /// Creating the Keychain item failed.
    case keychainWriteFailed
    /// AES-GCM sealing failed.
    case encryptionFailed
    /// AES-GCM opening or authentication failed.
    case decryptionFailed
    /// The stored value does not contain a valid TinyKV envelope.
    case invalidEnvelope
    /// The stored value uses an envelope version that is not supported.
    case unsupportedEnvelopeVersion
}

/// Encrypts and decrypts the value bytes stored by TinyKV.
public protocol TinyKVValueEncryptor: Sendable {
    /// Encrypts a value and authenticates the supplied record identity.
    /// - Parameters:
    ///   - data: Plaintext value bytes.
    ///   - associatedData: Non-secret record identity authenticated with the value.
    /// - Returns: The encrypted value bytes.
    /// - Throws: An encryptor-specific error when sealing fails.
    // TEST:TinyKVEncryptionTests[test_aesGCMEncryptor_roundTripsAndAuthenticates]
    func encrypt(_ data: Data, associatedData: Data) throws -> Data

    /// Decrypts a stored value and verifies its authenticated record identity.
    /// - Parameters:
    ///   - data: Encrypted value bytes.
    ///   - associatedData: The record identity used when the value was encrypted.
    /// - Returns: The plaintext value bytes.
    /// - Throws: An encryptor-specific error when the envelope or authentication is invalid.
    // TEST:TinyKVEncryptionTests[test_aesGCMEncryptor_rejectsTamperingAndWrongAssociatedData]
    func decrypt(_ data: Data, associatedData: Data) throws -> Data
}

/// AES-GCM implementation used by TinyKV for per-value authenticated encryption.
public struct TinyKVAESGCMEncryptor: TinyKVValueEncryptor, Sendable {
    private static let envelopeMagic = Data([0x52, 0x59, 0x4B, 0x56])
    private static let envelopeVersion: UInt8 = 1
    private static let keychainAccount = "default"

    private let key: SymmetricKey

    /// Creates an AES-GCM encryptor from a 256-bit symmetric key.
    /// - Parameter key: The 256-bit key used for sealing and opening values.
    /// - Throws: `TinyKVEncryptionError.invalidKey` when the key is not 256 bits.
    // TEST:TinyKVEncryptionTests[test_aesGCMEncryptor_roundTripsAndAuthenticates]
    public init(key: SymmetricKey) throws {
        let keyByteCount = key.withUnsafeBytes { buffer in
            buffer.count
        }
        guard keyByteCount == 32 else {
            throw TinyKVEncryptionError.invalidKey
        }
        self.key = key
    }

    /// Creates an AES-GCM encryptor from raw 256-bit key bytes.
    /// - Parameter keyData: Exactly 32 bytes of key material.
    /// - Throws: `TinyKVEncryptionError.invalidKey` when the data is not 32 bytes.
    public init(keyData: Data) throws {
        try self.init(key: SymmetricKey(data: keyData))
    }

    /// Loads a 256-bit key from Keychain or creates it on first use.
    /// - Parameter service: Stable Keychain service identifier for the store.
    /// - Returns: An AES-GCM encryptor backed by the Keychain key.
    /// - Throws: A `TinyKVEncryptionError` when Keychain access or key validation fails.
    // TEST:TinyKVEncryptionTests[test_keychainEncryptor_canLoadOrCreateKey]
    public static func loadOrCreateFromKeychain(service: String) throws -> TinyKVAESGCMEncryptor {
        guard !service.isEmpty else {
            throw TinyKVEncryptionError.invalidKeychainService
        }

        if let existingKeyData = try loadKeyDataFromKeychain(service: service) {
            return try TinyKVAESGCMEncryptor(keyData: existingKeyData)
        }

        let newKeyData = makeRandomKeyData()
        let addQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: keychainAccount,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
            kSecValueData as String: newKeyData
        ]
        let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
        if addStatus == errSecSuccess {
            return try TinyKVAESGCMEncryptor(keyData: newKeyData)
        }

        // Another process may have created the item between the read and add calls.
        if addStatus == errSecDuplicateItem,
           let existingKeyData = try loadKeyDataFromKeychain(service: service) {
            return try TinyKVAESGCMEncryptor(keyData: existingKeyData)
        }

        throw TinyKVEncryptionError.keychainWriteFailed
    }

    /// Seals a value with a fresh random nonce and authenticated record identity.
    /// - Parameters:
    ///   - data: Plaintext value bytes.
    ///   - associatedData: Non-secret record identity to authenticate.
    /// - Returns: Versioned TinyKV envelope containing the AES-GCM value.
    /// - Throws: `TinyKVEncryptionError.encryptionFailed` when sealing fails.
    public func encrypt(_ data: Data, associatedData: Data) throws -> Data {
        do {
            let sealedBox = try AES.GCM.seal(data, using: key, authenticating: associatedData)
            guard let combined = sealedBox.combined else {
                throw TinyKVEncryptionError.encryptionFailed
            }

            var envelope = Self.envelopeMagic
            envelope.append(Self.envelopeVersion)
            envelope.append(combined)
            return envelope
        } catch let error as TinyKVEncryptionError {
            throw error
        } catch {
            throw TinyKVEncryptionError.encryptionFailed
        }
    }

    /// Opens a TinyKV envelope and verifies its authenticated record identity.
    /// - Parameters:
    ///   - data: Versioned AES-GCM envelope from SQLite.
    ///   - associatedData: The record identity expected for the value.
    /// - Returns: Plaintext value bytes.
    /// - Throws: A `TinyKVEncryptionError` when the envelope or authentication is invalid.
    public func decrypt(_ data: Data, associatedData: Data) throws -> Data {
        let headerLength = Self.envelopeMagic.count + 1
        guard data.count > headerLength else {
            throw TinyKVEncryptionError.invalidEnvelope
        }
        guard Data(data.prefix(Self.envelopeMagic.count)) == Self.envelopeMagic else {
            throw TinyKVEncryptionError.invalidEnvelope
        }
        guard data[Self.envelopeMagic.count] == Self.envelopeVersion else {
            throw TinyKVEncryptionError.unsupportedEnvelopeVersion
        }

        let combined = Data(data.dropFirst(headerLength))
        do {
            let sealedBox = try AES.GCM.SealedBox(combined: combined)
            return try AES.GCM.open(sealedBox, using: key, authenticating: associatedData)
        } catch {
            throw TinyKVEncryptionError.decryptionFailed
        }
    }

    /// Reads raw key material from the Keychain generic-password item.
    /// - Parameter service: Stable Keychain service identifier.
    /// - Returns: Existing key bytes, or `nil` when the item does not exist.
    /// - Throws: `TinyKVEncryptionError` when the Keychain read fails.
    private static func loadKeyDataFromKeychain(service: String) throws -> Data? {
        var result: CFTypeRef?
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: keychainAccount,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound {
            return nil
        }
        guard status == errSecSuccess, let data = result as? Data else {
            throw TinyKVEncryptionError.keychainReadFailed
        }
        return data
    }

    /// Generates cryptographically random 256-bit key bytes for first-use storage.
    /// - Returns: Exactly 32 random key bytes.
    private static func makeRandomKeyData() -> Data {
        let key = SymmetricKey(size: .bits256)
        return key.withUnsafeBytes { buffer in
            Data(buffer)
        }
    }
}
