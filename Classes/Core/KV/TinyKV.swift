//
//  TinyKV.swift
//  RYKit
//
//  Created by mao rui on 2026/3/26.
//

import Foundation
import SQLite3

/// A lightweight SQLite-backed key-value store that persists `Codable` values as BLOB data.
public class TinyKV: TinyKVReadWritable {

    /// Runtime configuration for TinyKV persistence.
    public struct Config {
        /// Optional value encryptor. `nil` stores values without encryption.
        public let valueEncryptor: (any TinyKVValueEncryptor)?

        /// Creates a TinyKV configuration.
        /// - Parameter valueEncryptor: Optional encryptor applied to persisted values.
        // TEST:TinyKVTests[test_configNil_keepsPlaintextBehavior]
        public init(valueEncryptor: (any TinyKVValueEncryptor)? = nil) {
            self.valueEncryptor = valueEncryptor
        }
    }

    /// Errors that can be thrown by `TinyKV` read/query operations.
    public enum TinyKVError: Error, Equatable {
        /// Opening or creating the database file failed.
        case databaseOpenFailed
        /// Preparing a SQLite statement failed.
        case statementPrepareFailed
        /// Binding parameters to a SQLite statement failed.
        case statementBindFailed
        /// Executing a SQLite statement failed.
        case statementExecuteFailed
        /// No matching record was found.
        case notFound
        /// Decoding stored data into the requested type failed.
        case decodeFailed
        /// The provided integer key cannot fit into SQLite `INTEGER`.
        case intKeyOutOfRange
        /// The range expression for integer-key query is invalid.
        case invalidRangeExpression
        /// Encrypting a value before persistence failed.
        case encryptionFailed
        /// Decrypting a stored value or authenticating its record identity failed.
        case decryptionFailed
        /// The stored value uses an unsupported encryption envelope version.
        case unsupportedEncryptionFormat
    }

    private struct StoredRecord {
        /// Plaintext SQLite key reconstructed from the selected key columns.
        let key: TinyKVKey
        /// Raw value BLOB returned by SQLite before optional decryption.
        let data: Data
    }

    private let config: Config
    private let queue: DispatchQueue
    private let tableName: String
    private let quotedTableName: String
    private let databasePath: String
    private let encryptionNamespace: Data
    private var database: OpaquePointer?

    private let sqliteTransient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

    /// Creates a TinyKV instance and initializes its table and indexes if needed.
    /// - Parameters:
    ///   - dbName: Database file name (without extension).
    ///   - tableName: Target table name inside the database.
    ///   - config: Storage configuration. A `nil` value encryptor keeps plaintext behavior.
    // TEST:TinyKVTests[test_configNil_keepsPlaintextBehavior, test_encryptedValue_roundTrips]
    public init(dbName: String, tableName: String, config: Config = .init()) {
        self.config = config
        self.tableName = tableName
        self.quotedTableName = Self.quoteIdentifier(tableName)
        self.queue = DispatchQueue(label: "com.rykit.tinykv.\(dbName).\(tableName)")
        self.databasePath = Self.makeDatabasePath(dbName: dbName)
        self.encryptionNamespace = Self.makeEncryptionNamespace(dbName: dbName, tableName: tableName)

        do {
            try Self.createDatabaseDirectoryIfNeeded(for: databasePath)
            try openDatabaseIfNeeded()
            try setupTableIfNeeded()
        } catch {
            assertionFailure("TinyKV init failed: \(error)")
        }
    }

    deinit {
        if let db = database {
            sqlite3_close(db)
        }
    }

    /// Stores an encodable value for the given key. Existing value on the same key is replaced.
    /// - Parameters:
    ///   - value: Value to persist.
    ///   - key: String or integer key.
    public func set<T: Encodable>(value: T, for key: TinyKVKey) async throws {
        let data = try JSONEncoder().encode(value)
        try await set(data: data, for: key)
    }
    
    /// Stores raw encoded data for the given key. Existing value on the same key is replaced.
    /// - Parameters:
    ///   - data: Raw encoded value to persist before optional encryption.
    ///   - key: String or integer key.
    /// - Throws: `TinyKVError` when encryption or write fails.
    // TEST:TinyKVTests[test_encryptedValue_roundTrips, test_configNil_keepsPlaintextBehavior]
    public func set(data: Data, for key: TinyKVKey) async throws {
        try await runInQueue { [self] in
            try openDatabaseIfNeeded()
            let storedData = try encryptedData(data, for: key)
            switch key {
            case .string(let strKey):
                try upsert(data: storedData, stringKey: strKey)
            case .int(let intKey):
                try upsert(data: storedData, intKey: intKey)
            }
        }
    }

    /// Reads raw encoded data for a single key.
    /// - Parameter key: String or integer key.
    /// - Returns: Plaintext stored `Data` after optional decryption.
    /// - Throws: `TinyKVError` when query, decryption, or key lookup fails.
    // TEST:TinyKVTests[test_encryptedValue_roundTrips, test_wrongKey_failsDecryption]
    public func getData(for key: TinyKVKey) async throws -> Data {
        try await runInQueue { [self] in
            try openDatabaseIfNeeded()
            let storedData: Data
            switch key {
            case .string(let strKey):
                storedData = try queryData(sql: "SELECT value FROM \(quotedTableName) WHERE str_key = ? LIMIT 1;", bind: { stmt in
                    if sqlite3_bind_text(stmt, 1, strKey, -1, self.sqliteTransient) != SQLITE_OK {
                        throw TinyKVError.statementBindFailed
                    }
                })
            case .int(let intKey):
                let int64Key = try toInt64(intKey)
                storedData = try queryData(sql: "SELECT value FROM \(quotedTableName) WHERE int_key = ? LIMIT 1;", bind: { stmt in
                    if sqlite3_bind_int64(stmt, 1, int64Key) != SQLITE_OK {
                        throw TinyKVError.statementBindFailed
                    }
                })
            }
            return try decryptedData(storedData, for: key)
        }
    }

    /// Reads raw encoded data for all records matching the given range selector.
    /// - Parameters:
    ///   - rangeKey: String LIKE pattern or integer range expression.
    ///   - acend: Whether to sort ascending (`true`) or descending (`false`).
    /// - Returns: Ordered plaintext `Data` array after optional decryption.
    /// - Throws: `TinyKVError` when query or decryption fails.
    // TEST:TinyKVTests[test_encryptedRangeQueries_preserveTinyKVQueryKeyBehavior]
    public func getDatas(for rangeKey: TinyKVQueryKey, acend: Bool = true) async throws -> [Data] {
        try await runInQueue { [self] in
            try openDatabaseIfNeeded()
            let order = acend ? "ASC" : "DESC"
            let records: [StoredRecord]

            switch rangeKey {
            case TinyKVQueryKey.string(like: let like):
                let sql = "SELECT str_key, int_key, value FROM \(quotedTableName) WHERE str_key LIKE ? ORDER BY str_key \(order);"
                records = try queryStoredRecords(sql: sql, bind: { stmt in
                    if sqlite3_bind_text(stmt, 1, like, -1, self.sqliteTransient) != SQLITE_OK {
                        throw TinyKVError.statementBindFailed
                    }
                })
            case TinyKVQueryKey.strings(in: let keys):
                guard !keys.isEmpty else {
                    return []
                }
                let placeholders = Array(repeating: "?", count: keys.count).joined(separator: ",")
                let sql = "SELECT str_key, int_key, value FROM \(quotedTableName) WHERE str_key IN (\(placeholders)) ORDER BY str_key \(order);"
                records = try queryStoredRecords(sql: sql, bind: { stmt in
                    for (index, key) in keys.enumerated() {
                        if sqlite3_bind_text(stmt, Int32(index + 1), key, -1, self.sqliteTransient) != SQLITE_OK {
                            throw TinyKVError.statementBindFailed
                        }
                    }
                })
            case TinyKVQueryKey.int(condition: let condition):
                let validatedCondition = try validatedIntRangeCondition(from: condition)
                let sql = "SELECT str_key, int_key, value FROM \(quotedTableName) WHERE int_key IS NOT NULL AND (\(validatedCondition)) ORDER BY int_key \(order);"
                records = try queryStoredRecords(sql: sql)
            case TinyKVQueryKey.ints(in: let keys):
                guard !keys.isEmpty else {
                    return []
                }
                let int64Keys = try keys.map { try toInt64($0) }
                let placeholders = Array(repeating: "?", count: int64Keys.count).joined(separator: ",")
                let sql = "SELECT str_key, int_key, value FROM \(quotedTableName) WHERE int_key IN (\(placeholders)) ORDER BY int_key \(order);"
                records = try queryStoredRecords(sql: sql, bind: { stmt in
                    for (index, key) in int64Keys.enumerated() {
                        if sqlite3_bind_int64(stmt, Int32(index + 1), key) != SQLITE_OK {
                            throw TinyKVError.statementBindFailed
                        }
                    }
                })
            }

            return try records.map { record in
                try decryptedData(record.data, for: record.key)
            }
        }
    }

    /// Reads and decodes a single value for the given key.
    /// - Parameter key: String or integer key.
    /// - Returns: Decoded value of type `T`.
    /// - Throws: `TinyKVError.notFound` when key is missing, or `TinyKVError.decodeFailed` when decoding fails.
    public func getValue<T: Decodable>(for key: TinyKVKey) async throws -> T {
        let data = try await getData(for: key)
        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            throw TinyKVError.decodeFailed
        }
    }

    /// Reads and decodes all values matching the given range selector.
    /// - Parameters:
    ///   - rangeKey: String LIKE pattern or integer range expression.
    ///   - acend: Whether to sort ascending (`true`) or descending (`false`).
    /// - Returns: Ordered decoded values of type `T`.
    /// - Throws: `TinyKVError` when query or decoding fails.
    public func getValues<T: Decodable>(for rangeKey: TinyKVQueryKey, acend: Bool = true) async throws -> [T] {
        let datas = try await getDatas(for: rangeKey, acend: acend)
        let decoder = JSONDecoder()
        return try datas.map { data in
            do {
                return try decoder.decode(T.self, from: data)
            } catch {
                throw TinyKVError.decodeFailed
            }
        }
    }

    /// Removes one record matching the given key.
    /// - Parameter key: String or integer key.
    /// - Throws: `TinyKVError` when deletion fails.
    public func remove(for key: TinyKVKey) async throws {
        try await runInQueue { [self] in
            try openDatabaseIfNeeded()
            switch key {
            case .string(let strKey):
                try executePrepared(sql: "DELETE FROM \(quotedTableName) WHERE str_key = ?;") { stmt in
                    if sqlite3_bind_text(stmt, 1, strKey, -1, self.sqliteTransient) != SQLITE_OK {
                        throw TinyKVError.statementBindFailed
                    }
                }
            case .int(let intKey):
                let int64Key = try toInt64(intKey)
                try executePrepared(sql: "DELETE FROM \(quotedTableName) WHERE int_key = ?;") { stmt in
                    if sqlite3_bind_int64(stmt, 1, int64Key) != SQLITE_OK {
                        throw TinyKVError.statementBindFailed
                    }
                }
            }
        }
    }

    /// Removes all records matching the given range selector.
    /// - Parameter rangeKey: String LIKE pattern / string IN-set / integer condition / integer IN-set.
    /// - Throws: `TinyKVError` when deletion fails.
    public func remove(for rangeKey: TinyKVQueryKey) async throws {
        try await runInQueue { [self] in
            try openDatabaseIfNeeded()
            switch rangeKey {
            case .string(let like):
                try executePrepared(sql: "DELETE FROM \(quotedTableName) WHERE str_key LIKE ?;") { stmt in
                    if sqlite3_bind_text(stmt, 1, like, -1, self.sqliteTransient) != SQLITE_OK {
                        throw TinyKVError.statementBindFailed
                    }
                }
            case .strings(let keys):
                guard !keys.isEmpty else {
                    return
                }
                let placeholders = Array(repeating: "?", count: keys.count).joined(separator: ",")
                let sql = "DELETE FROM \(quotedTableName) WHERE str_key IN (\(placeholders));"
                try executePrepared(sql: sql) { stmt in
                    for (index, key) in keys.enumerated() {
                        if sqlite3_bind_text(stmt, Int32(index + 1), key, -1, self.sqliteTransient) != SQLITE_OK {
                            throw TinyKVError.statementBindFailed
                        }
                    }
                }
            case .int(let range):
                let condition = try validatedIntRangeCondition(from: range)
                let sql = "DELETE FROM \(quotedTableName) WHERE int_key IS NOT NULL AND (\(condition));"
                try execute(sql: sql)
            case .ints(let keys):
                guard !keys.isEmpty else {
                    return
                }
                let int64Keys = try keys.map { try toInt64($0) }
                let placeholders = Array(repeating: "?", count: int64Keys.count).joined(separator: ",")
                let sql = "DELETE FROM \(quotedTableName) WHERE int_key IN (\(placeholders));"
                try executePrepared(sql: sql) { stmt in
                    for (index, key) in int64Keys.enumerated() {
                        if sqlite3_bind_int64(stmt, Int32(index + 1), key) != SQLITE_OK {
                            throw TinyKVError.statementBindFailed
                        }
                    }
                }
            }
        }
    }

    /// Removes all records in this table.
    public func removeAll() async throws {
        try await runInQueue { [self] in
            try openDatabaseIfNeeded()
            try execute(sql: "DELETE FROM \(quotedTableName);")
        }
    }

    /// Returns total record count in this table.
    public func count() async throws -> Int {
        try await runInQueue { [self] in
            try openDatabaseIfNeeded()
            return try queryCount(sql: "SELECT COUNT(*) FROM \(quotedTableName);")
        }
    }

    /// Returns all stored keys.
    /// - Note: Non-empty `str_key` maps to `.string`; otherwise non-NULL `int_key` maps to `.int`.
    public func allKeys() async throws -> [TinyKVKey] {
        try await runInQueue { [self] in
            try openDatabaseIfNeeded()
            return try queryAllKeys()
        }
    }

    private func runInQueue<T>(_ block: @escaping () throws -> T) async throws -> T {
        try await withCheckedThrowingContinuation { continuation in
            queue.async {
                do {
                    continuation.resume(returning: try block())
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private func openDatabaseIfNeeded() throws {
        if database != nil {
            return
        }

        var db: OpaquePointer?
        let openFlags = SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX
        if sqlite3_open_v2(databasePath, &db, openFlags, nil) != SQLITE_OK {
            if let db {
                sqlite3_close(db)
            }
            throw TinyKVError.databaseOpenFailed
        }
        database = db
    }

    private func setupTableIfNeeded() throws {
        let createTableSQL = """
        CREATE TABLE IF NOT EXISTS \(quotedTableName) (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            str_key TEXT,
            int_key INTEGER,
            value BLOB NOT NULL
        );
        """
        try execute(sql: createTableSQL)

        let quotedStrIndex = Self.quoteIdentifier("idx_\(tableName)_str_key")
        let quotedIntIndex = Self.quoteIdentifier("idx_\(tableName)_int_key")

        try execute(sql: "CREATE UNIQUE INDEX IF NOT EXISTS \(quotedStrIndex) ON \(quotedTableName) (str_key);")
        try execute(sql: "CREATE UNIQUE INDEX IF NOT EXISTS \(quotedIntIndex) ON \(quotedTableName) (int_key);")
    }

    private func upsert(data: Data, stringKey: String) throws {
        let sql = """
        INSERT INTO \(quotedTableName) (str_key, int_key, value)
        VALUES (?, NULL, ?)
        ON CONFLICT(str_key)
        DO UPDATE SET value = excluded.value;
        """

        try executePrepared(sql: sql) { stmt in
            if sqlite3_bind_text(stmt, 1, stringKey, -1, sqliteTransient) != SQLITE_OK {
                throw TinyKVError.statementBindFailed
            }
            try bindBlob(data, to: stmt, index: 2)
        }
    }

    private func upsert(data: Data, intKey: Int) throws {
        let int64Key = try toInt64(intKey)
        let sql = """
        INSERT INTO \(quotedTableName) (str_key, int_key, value)
        VALUES (NULL, ?, ?)
        ON CONFLICT(int_key)
        DO UPDATE SET value = excluded.value;
        """

        try executePrepared(sql: sql) { stmt in
            if sqlite3_bind_int64(stmt, 1, int64Key) != SQLITE_OK {
                throw TinyKVError.statementBindFailed
            }
            try bindBlob(data, to: stmt, index: 2)
        }
    }

    private func queryData(sql: String, bind: ((OpaquePointer?) throws -> Void)? = nil) throws -> Data {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK else {
            throw TinyKVError.statementPrepareFailed
        }
        defer { sqlite3_finalize(statement) }

        if let bind {
            try bind(statement)
        }

        let stepResult = sqlite3_step(statement)
        if stepResult == SQLITE_ROW {
            return Self.dataFromBlobColumn(statement, index: 0)
        }
        if stepResult == SQLITE_DONE {
            throw TinyKVError.notFound
        }
        throw TinyKVError.statementExecuteFailed
    }

    /// Reads selected key/value rows so encrypted values can be opened with their record identity.
    /// - Parameters:
    ///   - sql: A SELECT statement returning `str_key`, `int_key`, and `value` in that order.
    ///   - bind: Optional statement binding closure.
    /// - Returns: Stored records containing their typed key and raw value BLOB.
    /// - Throws: `TinyKVError` when statement preparation, binding, or stepping fails.
    private func queryStoredRecords(sql: String, bind: ((OpaquePointer?) throws -> Void)? = nil) throws -> [StoredRecord] {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK else {
            throw TinyKVError.statementPrepareFailed
        }
        defer { sqlite3_finalize(statement) }

        if let bind {
            try bind(statement)
        }

        var records: [StoredRecord] = []
        while true {
            let stepResult = sqlite3_step(statement)
            if stepResult == SQLITE_ROW {
                guard let key = keyFromColumns(statement) else {
                    throw TinyKVError.statementExecuteFailed
                }
                let data = Self.dataFromBlobColumn(statement, index: 2)
                records.append(StoredRecord(key: key, data: data))
                continue
            }
            if stepResult == SQLITE_DONE {
                return records
            }
            throw TinyKVError.statementExecuteFailed
        }
    }

    private func queryCount(sql: String) throws -> Int {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK else {
            throw TinyKVError.statementPrepareFailed
        }
        defer { sqlite3_finalize(statement) }

        let stepResult = sqlite3_step(statement)
        guard stepResult == SQLITE_ROW else {
            throw TinyKVError.statementExecuteFailed
        }

        return Int(sqlite3_column_int64(statement, 0))
    }

    private func queryAllKeys() throws -> [TinyKVKey] {
        let sql = "SELECT str_key, int_key FROM \(quotedTableName);"
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK else {
            throw TinyKVError.statementPrepareFailed
        }
        defer { sqlite3_finalize(statement) }

        var keys: [TinyKVKey] = []
        while true {
            let stepResult = sqlite3_step(statement)
            if stepResult == SQLITE_ROW {
                if sqlite3_column_type(statement, 0) != SQLITE_NULL,
                   let cString = sqlite3_column_text(statement, 0) {
                    let str = String(cString: cString)
                    keys.append(.string(str))
                    continue
                }

                if sqlite3_column_type(statement, 1) != SQLITE_NULL {
                    let intValue = sqlite3_column_int64(statement, 1)
                    if let intKey = Int(exactly: intValue) {
                        keys.append(.int(intKey))
                    }
                }
                continue
            }
            if stepResult == SQLITE_DONE {
                return keys
            }
            throw TinyKVError.statementExecuteFailed
        }
    }

    /// Encrypts a value when the configuration supplies an encryptor.
    /// - Parameters:
    ///   - data: Plaintext value bytes.
    ///   - key: Storage key used to bind the ciphertext identity.
    /// - Returns: Data ready to bind to SQLite.
    /// - Throws: `TinyKVError.encryptionFailed` when the configured encryptor fails.
    private func encryptedData(_ data: Data, for key: TinyKVKey) throws -> Data {
        guard let encryptor = config.valueEncryptor else {
            return data
        }

        do {
            return try encryptor.encrypt(data, associatedData: associatedData(for: key))
        } catch {
            throw TinyKVError.encryptionFailed
        }
    }

    /// Decrypts a value when the configuration supplies an encryptor.
    /// - Parameters:
    ///   - data: Raw value BLOB returned by SQLite.
    ///   - key: Storage key used to authenticate the ciphertext identity.
    /// - Returns: Plaintext value bytes.
    /// - Throws: A decryption-related `TinyKVError` when authentication fails.
    private func decryptedData(_ data: Data, for key: TinyKVKey) throws -> Data {
        guard let encryptor = config.valueEncryptor else {
            return data
        }

        do {
            return try encryptor.decrypt(data, associatedData: associatedData(for: key))
        } catch let error as TinyKVEncryptionError where error == .unsupportedEnvelopeVersion {
            throw TinyKVError.unsupportedEncryptionFormat
        } catch {
            throw TinyKVError.decryptionFailed
        }
    }

    /// Builds canonical non-secret identity bytes for AES-GCM Associated Data.
    /// - Parameter key: String or integer storage key.
    /// - Returns: Length-delimited database, table, key-type, and key bytes.
    private func associatedData(for key: TinyKVKey) -> Data {
        var data = Data([0x01])
        Self.appendLengthPrefixed(encryptionNamespace, to: &data)

        switch key {
        case .string(let value):
            data.append(0x00)
            Self.appendLengthPrefixed(Data(value.utf8), to: &data)
        case .int(let value):
            data.append(0x01)
            Self.appendLengthPrefixed(Data(String(value).utf8), to: &data)
        }

        return data
    }

    /// Reconstructs the typed key from the first two columns of a range-query row.
    /// - Parameter statement: SQLite statement positioned on a result row.
    /// - Returns: The stored key, or `nil` for an invalid row.
    private func keyFromColumns(_ statement: OpaquePointer?) -> TinyKVKey? {
        if sqlite3_column_type(statement, 0) != SQLITE_NULL,
           let cString = sqlite3_column_text(statement, 0) {
            return .string(String(cString: cString))
        }

        guard sqlite3_column_type(statement, 1) != SQLITE_NULL else {
            return nil
        }
        let intValue = sqlite3_column_int64(statement, 1)
        guard let intKey = Int(exactly: intValue) else {
            return nil
        }
        return .int(intKey)
    }

    /// Creates a stable namespace for values stored in one database/table pair.
    /// - Parameters:
    ///   - dbName: Logical database name supplied by the caller.
    ///   - tableName: Logical table name supplied by the caller.
    /// - Returns: Length-delimited namespace bytes.
    private static func makeEncryptionNamespace(dbName: String, tableName: String) -> Data {
        var namespace = Data()
        appendLengthPrefixed(Data(dbName.utf8), to: &namespace)
        appendLengthPrefixed(Data(tableName.utf8), to: &namespace)
        return namespace
    }

    /// Appends a length-delimited byte sequence to a canonical identity buffer.
    /// - Parameters:
    ///   - value: Bytes to append.
    ///   - data: Destination identity buffer.
    private static func appendLengthPrefixed(_ value: Data, to data: inout Data) {
        var length = UInt64(value.count).bigEndian
        withUnsafeBytes(of: &length) { bytes in
            data.append(contentsOf: bytes)
        }
        data.append(value)
    }

    private func validatedIntRangeCondition(from raw: String) throws -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            throw TinyKVError.invalidRangeExpression
        }
        let condition = trimmed.replacingOccurrences(of: "$", with: "int_key")

        let term = #"\(?\s*int_key\s*(?:<=|>=|!=|=|<|>)\s*-?\d+\s*\)?"#
        let whitelistPattern = #"^\s*"# + term + #"(?:\s+(?:AND|OR)\s+"# + term + #")*\s*$"#
        guard condition.range(of: whitelistPattern, options: .regularExpression) != nil else {
            throw TinyKVError.invalidRangeExpression
        }

        return condition
    }


    private func execute(sql: String) throws {
        guard sqlite3_exec(database, sql, nil, nil, nil) == SQLITE_OK else {
            throw TinyKVError.statementExecuteFailed
        }
    }

    private func executePrepared(sql: String, bind: (OpaquePointer?) throws -> Void) throws {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK else {
            throw TinyKVError.statementPrepareFailed
        }
        defer { sqlite3_finalize(statement) }

        try bind(statement)

        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw TinyKVError.statementExecuteFailed
        }
    }

    private func bindBlob(_ data: Data, to statement: OpaquePointer?, index: Int32) throws {
        let result = data.withUnsafeBytes { rawBuffer -> Int32 in
            let baseAddress = rawBuffer.baseAddress
            return sqlite3_bind_blob(statement, index, baseAddress, Int32(data.count), sqliteTransient)
        }
        if result != SQLITE_OK {
            throw TinyKVError.statementBindFailed
        }
    }

    private func toInt64(_ value: Int) throws -> Int64 {
        let int64Value = Int64(value)
        if Int(int64Value) != value {
            throw TinyKVError.intKeyOutOfRange
        }
        return int64Value
    }

    private static func dataFromBlobColumn(_ statement: OpaquePointer?, index: Int32) -> Data {
        let count = Int(sqlite3_column_bytes(statement, index))
        guard count > 0, let bytes = sqlite3_column_blob(statement, index) else {
            return Data()
        }
        return Data(bytes: bytes, count: count)
    }

    private static func quoteIdentifier(_ value: String) -> String {
        let escaped = value.replacingOccurrences(of: "\"", with: "\"\"")
        return "\"\(escaped)\""
    }

    private static func createDatabaseDirectoryIfNeeded(for databasePath: String) throws {
        let databaseURL = URL(fileURLWithPath: databasePath)
        let directoryURL = databaseURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
    }

    private static func makeDatabasePath(dbName: String) -> String {
        let safeDBName = dbName.replacingOccurrences(of: "/", with: "_")
        let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
        let baseURL = (documentsURL ?? FileManager.default.temporaryDirectory)
            .appendingPathComponent("rykit", isDirectory: true)
            .appendingPathComponent("tinykv", isDirectory: true)
        let dbURL = baseURL.appendingPathComponent("\(safeDBName).db")
        return dbURL.path
    }
}
