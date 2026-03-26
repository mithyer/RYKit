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
        /// The provided unsigned integer key cannot fit into SQLite `INTEGER`.
        case intKeyOutOfRange
        /// The range expression for integer-key query is invalid.
        case invalidRangeExpression
    }

    private let queue: DispatchQueue
    private let tableName: String
    private let quotedTableName: String
    private let databasePath: String
    private var database: OpaquePointer?

    private let sqliteTransient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

    /// Creates a TinyKV instance and initializes its table and indexes if needed.
    /// - Parameters:
    ///   - dbName: Database file name (without extension).
    ///   - tableName: Target table name inside the database.
    public init(dbName: String, tableName: String) {
        self.tableName = tableName
        self.quotedTableName = Self.quoteIdentifier(tableName)
        self.queue = DispatchQueue(label: "com.rykit.tinykv.\(dbName).\(tableName)")
        self.databasePath = Self.makeDatabasePath(dbName: dbName)

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
    ///   - data: Raw payload to persist.
    ///   - key: String or integer key.
    /// - Throws: `TinyKVError` when write fails.
    public func set(data: Data, for key: TinyKVKey) async throws {
        try await runInQueue { [self] in
            try openDatabaseIfNeeded()
            switch key {
            case .string(let strKey):
                try upsert(data: data, stringKey: strKey)
            case .int(let intKey):
                try upsert(data: data, intKey: intKey)
            }
        }
    }

    /// Reads raw encoded data for a single key.
    /// - Parameter key: String or integer key.
    /// - Returns: Stored raw `Data`.
    /// - Throws: `TinyKVError` when query fails or key is missing.
    public func getData(for key: TinyKVKey) async throws -> Data {
        try await runInQueue { [self] in
            try openDatabaseIfNeeded()
            switch key {
            case .string(let strKey):
                return try queryData(sql: "SELECT value FROM \(quotedTableName) WHERE str_key = ? LIMIT 1;", bind: { stmt in
                    if sqlite3_bind_text(stmt, 1, strKey, -1, self.sqliteTransient) != SQLITE_OK {
                        throw TinyKVError.statementBindFailed
                    }
                })
            case .int(let intKey):
                let int64Key = try toInt64(intKey)
                return try queryData(sql: "SELECT value FROM \(quotedTableName) WHERE int_key = ? LIMIT 1;", bind: { stmt in
                    if sqlite3_bind_int64(stmt, 1, int64Key) != SQLITE_OK {
                        throw TinyKVError.statementBindFailed
                    }
                })
            }
        }
    }

    /// Reads raw encoded data for all records matching the given range selector.
    /// - Parameters:
    ///   - rangeKey: String LIKE pattern or integer range expression.
    ///   - acend: Whether to sort ascending (`true`) or descending (`false`).
    /// - Returns: Ordered raw `Data` array.
    /// - Throws: `TinyKVError` when query fails.
    public func getDatas(for rangeKey: TinyKVRangeKey, acend: Bool = true) async throws -> [Data] {
        try await runInQueue { [self] in
            try openDatabaseIfNeeded()
            let order = acend ? "ASC" : "DESC"

            switch rangeKey {
            case .string(let like):
                let sql = "SELECT value FROM \(quotedTableName) WHERE str_key LIKE ? ORDER BY str_key \(order);"
                return try queryDatas(sql: sql, bind: { stmt in
                    if sqlite3_bind_text(stmt, 1, like, -1, self.sqliteTransient) != SQLITE_OK {
                        throw TinyKVError.statementBindFailed
                    }
                })
            case .int(let range):
                guard range.contains("$") else {
                    throw TinyKVError.invalidRangeExpression
                }
                let condition = range.replacingOccurrences(of: "$", with: "int_key")
                let sql = "SELECT value FROM \(quotedTableName) WHERE int_key IS NOT NULL AND (\(condition)) ORDER BY int_key \(order);"
                return try queryDatas(sql: sql)
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
    public func getValues<T: Decodable>(for rangeKey: TinyKVRangeKey, acend: Bool = true) async throws -> [T] {
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

    private func upsert(data: Data, intKey: UInt) throws {
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

    private func queryDatas(sql: String, bind: ((OpaquePointer?) throws -> Void)? = nil) throws -> [Data] {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK else {
            throw TinyKVError.statementPrepareFailed
        }
        defer { sqlite3_finalize(statement) }

        if let bind {
            try bind(statement)
        }

        var values: [Data] = []
        while true {
            let stepResult = sqlite3_step(statement)
            if stepResult == SQLITE_ROW {
                values.append(Self.dataFromBlobColumn(statement, index: 0))
                continue
            }
            if stepResult == SQLITE_DONE {
                return values
            }
            throw TinyKVError.statementExecuteFailed
        }
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

    private func toInt64(_ value: UInt) throws -> Int64 {
        guard let int64Value = Int64(exactly: value) else {
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
