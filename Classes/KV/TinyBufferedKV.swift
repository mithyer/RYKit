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

    private let config: Config
    private let tinyKV: TinyKV
    private var buffer = [TinyKV.Key: Data]()

    public init(dbName: String, tableName: String, config: Config = .init()) {
        self.config = config
        self.tinyKV = TinyKV(dbName: dbName, tableName: tableName)
    }

    public func set<T: Encodable>(value: T, for key: TinyKV.Key) async throws {
        try await set(data: JSONEncoder().encode(value), for: key)
    }

    public func set(data: Data, for key: TinyKV.Key) async throws {
        fatalError("TinyBufferedKV.set(data:for:) is not implemented")
    }

    public func flush() async throws {
        fatalError("TinyBufferedKV.flush() is not implemented")
    }

    public func getData(for key: TinyKV.Key) async throws -> Data {
        fatalError("TinyBufferedKV.getData(for:) is not implemented")
    }

    public func getDatas(for rangeKey: TinyKV.RangeKey, acend: Bool = true) async throws -> [Data] {
        fatalError("TinyBufferedKV.getDatas(for:acend:) is not implemented")
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
}
