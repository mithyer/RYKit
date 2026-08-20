# TinyKV Value Encryption Implementation Plan

> **Scope:** Encrypt persisted values only with per-record AES-GCM. Keep SQLite keys and query semantics unchanged. Legacy plaintext records are explicitly out of scope.

**Goal:** Add opt-in AES-GCM encryption for `TinyKV` and `TinyBufferedKV` values while preserving the existing `TinyKVReadWritable` interface and all `TinyKVQueryKey` query behavior.

**Architecture:** Introduce a small value-encryption seam backed by `CryptoKit.AES.GCM`. `TinyKV` encrypts data immediately before binding it to SQLite and decrypts data immediately after reading it. SQLite continues to store `str_key` and `int_key` in plaintext so equality, `LIKE`, `IN`, range, ordering, deletion, and key enumeration continue to work. A Keychain-backed key provider creates the encryptor instance; that instance is injected through `Config` rather than being created by `TinyKV` itself.

**Security boundary:** This protects value contents at rest. It does not hide keys, table names, record counts, indexes, ordering, or access patterns. `TinyBufferedKV` continues to hold plaintext values in its in-memory buffer in this first version.

**Tech Stack:** Swift, Foundation, CryptoKit, Security, SQLite3, XCTest

---

## Fixed Decisions

- Use `CryptoKit.AES.GCM` with a 256-bit symmetric key.
- Generate a fresh random nonce for every value write.
- Authenticate the value with AES-GCM's authentication tag.
- Include a versioned envelope around `AES.GCM.SealedBox.combined`.
- Use typed record identity as Associated Data: database identity, table name, key type, and key value.
- Keep `TinyKVKey`, `TinyKVQueryKey`, and `TinyKVReadWritable` source-level behavior unchanged.
- Keep encryption opt-in through `Config.valueEncryptor`; `nil` means values remain unencrypted.
- Do not read, migrate, or silently fall back to legacy plaintext records in encrypted mode.
- Do not encrypt key columns and do not introduce SQLCipher.
- Do not encrypt the `TinyBufferedKV` memory buffer in this version.

An encrypted instance must not share the same database/table with an unencrypted instance. Callers should use a new `dbName`/`tableName` or clear the existing table before enabling encryption.

---

## File Structure

- Add: `Classes/Core/KV/TinyKVEncryption.swift`
  - Value-encryption protocol.
  - AES-GCM implementation.
  - Versioned envelope encoding and decoding.
  - Keychain-backed key loading and first-use key creation.
- Modify: `Classes/Core/KV/TinyKV.swift`
  - Add `TinyKV.Config` with an optional `valueEncryptor` protocol instance.
  - Accept the config without changing the existing default initializer call shape.
  - Encrypt in the common `set(data:for:)` persistence path.
  - Decrypt single-key and range-query results.
  - Add encryption-related `TinyKVError` cases.
  - Preserve key columns and SQL query behavior.
- Modify: `Classes/Core/KV/TinyBufferedKV.swift`
  - Accept and forward the value encryptor to its internal `TinyKV`.
  - Keep buffered data plaintext until `flush()` delegates to `TinyKV`.
- Add or modify: `Project/RYKitTests/TinyKVEncryptionTests.swift`
  - Test the AES-GCM value encryptor and envelope independently.
- Modify: `Project/RYKitTests/TinyKVTests.swift`
  - Test encrypted persistence, decryption failures, and all query variants.
- Modify: `Project/RYKitTests/TinyBufferedKVTests.swift`
  - Test encrypted flush and buffered reads.
- Modify: `README.md`
  - Document encrypted construction, key storage, query visibility, and the no-legacy constraint.

`Package.swift` should not require a third-party dependency. `CryptoKit` and `Security` are system frameworks for the supported Apple deployment targets.

## Configuration Shape

The encryption protocol instance is supplied through the store configuration:

```swift
let encryptor = try TinyKVAESGCMEncryptor.loadOrCreateFromKeychain(service: "com.example.app.tinykv")
let config = TinyKV.Config(valueEncryptor: encryptor)
let kv = TinyKV(dbName: "app", tableName: "secure-cache", config: config)
```

`TinyKV.Config(valueEncryptor: nil)` means no encryption. `TinyBufferedKV.Config` exposes the same `valueEncryptor` property and forwards it to its internal `TinyKV`. Keychain access remains outside the storage implementation; it only creates or loads the protocol instance that is injected into `Config`.

The injected protocol instance is the only encryption seam used by the stores. Custom implementations may be supplied for testing or alternate key management, while the built-in AES-GCM implementation remains the recommended production implementation.

---

## Task 1: Define the Encryption Interface and Envelope

**Files:**
- Add `Classes/Core/KV/TinyKVEncryption.swift`
- Add `Project/RYKitTests/TinyKVEncryptionTests.swift`

- [ ] **Step 1: Add failing primitive tests**

Cover:

- Plaintext can be encrypted and decrypted with the same key.
- Two encryptions of the same plaintext produce different ciphertext because the nonce is random.
- A wrong key fails authentication.
- Changing one ciphertext byte fails authentication.
- Changing Associated Data fails authentication.
- A malformed or unsupported envelope version is rejected.

- [ ] **Step 2: Define the small encryption seam**

Use a protocol equivalent to:

```swift
public protocol TinyKVValueEncryptor: Sendable {
    func encrypt(_ data: Data, associatedData: Data) throws -> Data
    func decrypt(_ data: Data, associatedData: Data) throws -> Data
}
```

The protocol must operate on raw `Data` so both `set(value:)` and `set(data:)` share the same persistence path.

- [ ] **Step 3: Implement the AES-GCM envelope**

Use a compact envelope with:

```text
magic bytes + format version + AES.GCM.SealedBox.combined
```

The implementation must:

- Generate a new nonce for each `encrypt` call.
- Use `AES.GCM.seal(_:using:authenticating:)`.
- Reconstruct the sealed box from the stored combined representation.
- Reject missing magic bytes, unsupported versions, malformed combined data, and authentication failures.
- Map cryptographic failures to stable library errors rather than exposing raw CryptoKit errors.

- [ ] **Step 4: Implement Keychain key loading**

Add a Keychain helper that:

- Uses a caller-provided service identifier.
- Loads an existing 32-byte key.
- Creates and stores a random 32-byte key only when the item is absent.
- Treats all other Keychain failures as errors.
- Uses `kSecAttrAccessibleWhenUnlockedThisDeviceOnly` by default.
- Does not store the key in SQLite, UserDefaults, or the encrypted value table.

The core encryptor should also support direct `SymmetricKey` injection so tests do not depend on global Keychain state.

- [ ] **Step 5: Run primitive tests**

Run:

```bash
xcodebuild test -project Project/RYKit.xcodeproj -scheme RYKitTests -destination 'platform=macOS' -only-testing:RYKitTests/TinyKVEncryptionTests
```

Expected: all primitive encryption tests pass.

---

## Task 2: Integrate Encryption into TinyKV

**Files:**
- Modify `Classes/Core/KV/TinyKV.swift`
- Modify `Project/RYKitTests/TinyKVTests.swift`

- [ ] **Step 1: Add encrypted TinyKV tests**

Cover:

- `set(value:)` and `getValue(for:)` round-trip through encrypted storage.
- `set(data:)` and `getData(for:)` round-trip through encrypted storage.
- The SQLite value BLOB is not the original plaintext JSON.
- Recreating `TinyKV` with the same key can read persisted values.
- Recreating it with a different key fails with `decryptionFailed`.
- A tampered BLOB fails with `decryptionFailed`.
- An encrypted instance rejects an unencrypted record; no legacy fallback is attempted.

- [ ] **Step 2: Add the optional encryptor through `TinyKV.Config`**

Add a nested `TinyKV.Config` containing:

```swift
public struct Config {
    public let valueEncryptor: (any TinyKVValueEncryptor)?

    public init(valueEncryptor: (any TinyKVValueEncryptor)? = nil) {
        self.valueEncryptor = valueEncryptor
    }
}
```

Update the store initializer to accept `config: Config = .init()`. `config.valueEncryptor == nil` must preserve the current plaintext behavior. A configured protocol instance must be retained and used for every value write and read.

The public data contract remains:

```text
set(value:) / set(data:) accept plaintext
getData() / getValue() return plaintext
```

The encryptor must not be applied to keys or SQL query parameters.

- [ ] **Step 3: Add stable encryption errors**

Extend `TinyKV.TinyKVError` with cases equivalent to:

```swift
case encryptionFailed
case decryptionFailed
case unsupportedEncryptionFormat
case encryptionKeyUnavailable
```

Use these errors consistently for write, read, malformed-envelope, and Keychain failures.

- [ ] **Step 4: Encrypt at the common write boundary**

In `set(data:for:)`:

1. Open the database as before.
2. Build canonical typed Associated Data from the database/table identity and `TinyKVKey`.
3. Encrypt the input data when an encryptor is configured.
4. Pass only the encrypted data to `upsert`.

No plaintext value may reach `bindBlob` in encrypted mode.

- [ ] **Step 5: Decrypt single-key reads**

In `getData(for:)`:

1. Query the same plaintext key columns as today.
2. Read the stored BLOB.
3. Build the same Associated Data from the requested key.
4. Decrypt and return the plaintext data.

- [ ] **Step 6: Decrypt range-query reads without changing query semantics**

Change the internal range-query result to include the selected key with the value:

```sql
SELECT str_key, int_key, value FROM ...
```

For each row:

1. Reconstruct `TinyKVKey` from `str_key` or `int_key`.
2. Build its Associated Data.
3. Decrypt the value.
4. Return only `[Data]` to the existing public method.

Keep all existing SQL predicates and ordering unchanged:

- `str_key LIKE ?`
- `str_key IN (...)`
- validated `int_key` conditions
- `int_key IN (...)`
- ascending and descending ordering

- [ ] **Step 7: Keep non-value operations unchanged**

`remove`, `removeAll`, `count`, and `allKeys` do not need decryption because they operate on key columns or table metadata. `TinyKVQueryKey` and `KVProtocols.swift` should not be modified.

- [ ] **Step 8: Run TinyKV tests**

Run:

```bash
xcodebuild test -project Project/RYKit.xcodeproj -scheme RYKitTests -destination 'platform=macOS' -only-testing:RYKitTests/TinyKVTests
```

Expected: existing and new TinyKV tests pass.

---

## Task 3: Propagate the Encryptor through TinyBufferedKV

**Files:**
- Modify `Classes/Core/KV/TinyBufferedKV.swift`
- Modify `Project/RYKitTests/TinyBufferedKVTests.swift`

- [ ] **Step 1: Add encrypted buffered-store tests**

Cover:

- A buffered write is readable from the in-memory buffer before flush.
- After flush, the underlying SQLite BLOB is encrypted.
- A new encrypted `TinyBufferedKV` instance can read the flushed value.
- Range queries flush first and return decrypted values.
- The existing debounce and threshold flush behavior is unchanged.
- Values are not encrypted twice during flush.

- [ ] **Step 2: Add the encryptor to `TinyBufferedKV.Config`**

Extend the existing buffer configuration with:

```swift
public let valueEncryptor: (any TinyKVValueEncryptor)?
```

The initializer must default this property to `nil`, preserving current plaintext behavior. `TinyBufferedKV` forwards the configured instance to `TinyKV.Config(valueEncryptor:)` when constructing its internal storage.

The configured protocol instance must be the same instance used by the underlying store. Do not create a second encryptor or load Keychain state inside `TinyBufferedKV`.

- [ ] **Step 3: Preserve buffer semantics**

Keep the buffer as plaintext `Data`:

```text
set(data:) -> plaintext buffer
getData() -> plaintext buffer hit
flush() -> TinyKV.set(data:) -> AES-GCM -> SQLite
```

Do not add encryption to `flushWriteHook`; the normal storage path must remain responsible for persistence encryption.

- [ ] **Step 4: Run buffered-store tests**

Run:

```bash
xcodebuild test -project Project/RYKit.xcodeproj -scheme RYKitTests -destination 'platform=macOS' -only-testing:RYKitTests/TinyBufferedKVTests
```

Expected: all existing and new TinyBufferedKV tests pass.

---

## Task 4: Document and Verify the Feature

**Files:**
- Modify `README.md`
- Test `Project/RYKitTests/TinyKVEncryptionTests.swift`
- Test `Project/RYKitTests/TinyKVTests.swift`
- Test `Project/RYKitTests/TinyBufferedKVTests.swift`

- [ ] **Step 1: Document usage**

Document:

- That `TinyKV.Config.valueEncryptor == nil` means no encryption.
- How to load or create the Keychain-backed encryptor instance.
- How to pass the instance through `TinyKV.Config` and `TinyBufferedKV.Config`.
- That callers still pass and receive plaintext values through the API.
- That SQLite keys and query metadata remain visible.
- That encrypted and unencrypted instances must not share a database/table.
- That legacy plaintext records are unsupported and are not migrated.
- That loss of the Keychain key means the values cannot be decrypted.

- [ ] **Step 2: Run the combined regression suite**

Run:

```bash
xcodebuild test -project Project/RYKit.xcodeproj -scheme RYKitTests -destination 'platform=macOS' -only-testing:RYKitTests/TinyKVEncryptionTests -only-testing:RYKitTests/TinyKVTests -only-testing:RYKitTests/TinyBufferedKVTests
```

Expected: `** TEST SUCCEEDED **`.

- [ ] **Step 3: Review the final diff**

Verify:

- No SQLCipher or third-party dependency was added.
- No key column was encrypted or renamed.
- No query behavior was removed.
- No legacy plaintext fallback was introduced.
- No plaintext value is bound to SQLite in encrypted mode.
- Public method documentation describes the encryption configuration and errors.

---

## Acceptance Criteria

- `TinyKV` can persist and read AES-GCM encrypted values with a Keychain-backed key.
- The same plaintext written twice produces different stored ciphertext.
- Wrong-key reads and tampered values fail closed.
- String and integer keys remain queryable through all existing `TinyKVQueryKey` cases.
- `TinyBufferedKV` encrypts only when data crosses into persistent storage.
- Existing no-encryption construction remains source-compatible, with `Config.valueEncryptor == nil` selecting plaintext storage.
- No legacy plaintext migration or fallback exists.
- Tests verify encrypted BLOBs, authenticated failure, persistence, range queries, and buffered flush behavior.
