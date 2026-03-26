//
//  KVProtocols.swift
//  RYKit
//
//  Created by Codex on 2026/3/26.
//

import Foundation

/// Key type for single-record read/write operations.
///
/// - `string`: Uses `TEXT` key path in storage.
/// - `int`: Uses `INTEGER` key path in storage.
public enum TinyKVKey {
    /// String key, suitable for business IDs or namespaced keys (for example: `"user:1001"`).
    case string(String)
    /// Unsigned integer key, suitable for numeric IDs.
    case int(UInt)
}

/// Selector type for range queries.
///
/// - `string(like:)`: SQL `LIKE` pattern match on string keys.
/// - `int(range:)`: SQL condition template for integer keys.
public enum TinyKVRangeKey {
    /// SQL `LIKE` pattern for string keys (for example: `"user:%"`).
    case string(like: String)
    /// SQL condition template for integer keys; `$` is replaced by the concrete integer key column in storage.
    /// Example: `"$ >= 100 AND $ < 200"`.
    case int(range: String)
}

public protocol TinyKVReadWritable {
    func set<T: Encodable>(value: T, for key: TinyKVKey) async throws
    func set(data: Data, for key: TinyKVKey) async throws
    func getData(for key: TinyKVKey) async throws -> Data
    func getDatas(for rangeKey: TinyKVRangeKey, acend: Bool) async throws -> [Data]
    func getValue<T: Decodable>(for key: TinyKVKey) async throws -> T
    func getValues<T: Decodable>(for rangeKey: TinyKVRangeKey, acend: Bool) async throws -> [T]
}

public protocol TinyKVFlushable {
    func flush() async throws
}
