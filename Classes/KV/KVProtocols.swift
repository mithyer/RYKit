//
//  KVProtocols.swift
//  RYKit
//
//  Created by Codex on 2026/3/26.
//

import Foundation

public enum KVKey {
    case string(String)
    case int(UInt)
}

public enum KVRangeKey {
    case string(like: String)
    case int(range: String)
}

public protocol KVReadableWritableStore {
    func set<T: Encodable>(value: T, for key: KVKey) async throws
    func set(data: Data, for key: KVKey) async throws
    func getData(for key: KVKey) async throws -> Data
    func getDatas(for rangeKey: KVRangeKey, acend: Bool) async throws -> [Data]
    func getValue<T: Decodable>(for key: KVKey) async throws -> T
    func getValues<T: Decodable>(for rangeKey: KVRangeKey, acend: Bool) async throws -> [T]
}

public protocol KVFlushableStore {
    func flush() async throws
}
