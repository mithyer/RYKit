//
//  TinyBufferedKV.swift
//  RYKit
//
//  Created by Codex on 2026/3/26.
//

import Foundation

public final class TinyBufferedKV {

    public struct Config {
        public let bufferLimit: Int

        public init(bufferLimit: Int = 2) {
            self.bufferLimit = bufferLimit
        }
    }

    public enum TinyBufferedKVError: Error {
        case notImplemented
    }

    private enum BufferKey: Hashable {
        case string(String)
        case int(UInt)
    }

    private let config: Config
    private let storage: TinyKV
    private var buffer = [BufferKey: Data]()
    private let queue = DispatchQueue(label: "com.rykit.tinybufferedkv")

    public init(dbName: String, tableName: String, config: Config = .init()) {
        self.config = config
        self.storage = TinyKV(dbName: dbName, tableName: tableName)
    }

    public func set<T: Encodable>(value: T, for key: TinyKV.Key) async throws {
        try await set(data: JSONEncoder().encode(value), for: key)
    }

    public func set(data: Data, for key: TinyKV.Key) async throws {
        let bufferKey = canonicalKey(for: key)
        queue.sync {
            buffer[bufferKey] = data
        }
    }

    public func flush() async throws {
        throw TinyBufferedKVError.notImplemented
    }

    public func getData(for key: TinyKV.Key) async throws -> Data {
        let bufferKey = canonicalKey(for: key)
        if let data = queue.sync(execute: { buffer[bufferKey] }) {
            return data
        }
        return try await storage.getData(for: key)
    }

    public func getDatas(for rangeKey: TinyKV.RangeKey, acend: Bool = true) async throws -> [Data] {
        return try await storage.getDatas(for: rangeKey, acend: acend)
    }

    public func getValue<T: Decodable>(for key: TinyKV.Key) async throws -> T {
        let data = try await getData(for: key)
        return try JSONDecoder().decode(T.self, from: data)
    }

    public func getValues<T: Decodable>(for rangeKey: TinyKV.RangeKey, acend: Bool = true) async throws -> [T] {
        let datas = try await getDatas(for: rangeKey, acend: acend)
        let decoder = JSONDecoder()
        return try datas.map { try decoder.decode(T.self, from: $0) }
    }

    private func canonicalKey(for key: TinyKV.Key) -> BufferKey {
        switch key {
        case .string(let value):
            return .string(value)
        case .int(let value):
            return .int(value)
        }
    }

}
