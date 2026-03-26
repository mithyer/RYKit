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

    private struct BufferedKey: Hashable {
        let key: TinyKV.Key

        init(_ key: TinyKV.Key) {
            self.key = key
        }

        static func == (lhs: BufferedKey, rhs: BufferedKey) -> Bool {
            switch (lhs.key, rhs.key) {
            case let (.string(lhsValue), .string(rhsValue)):
                return lhsValue == rhsValue
            case let (.int(lhsValue), .int(rhsValue)):
                return lhsValue == rhsValue
            default:
                return false
            }
        }

        func hash(into hasher: inout Hasher) {
            switch key {
            case .string(let value):
                hasher.combine(0)
                hasher.combine(value)
            case .int(let value):
                hasher.combine(1)
                hasher.combine(value)
            }
        }
    }

    private let config: Config
    private let tinyKV: TinyKV
    private var buffer = [BufferedKey: Data]()
    private let bufferQueue = DispatchQueue(label: "com.rykit.tinybufferedkv.buffer", attributes: .concurrent)

    public init(dbName: String, tableName: String, config: Config = .init()) {
        self.config = config
        self.tinyKV = TinyKV(dbName: dbName, tableName: tableName)
    }

    public func set<T: Encodable>(value: T, for key: TinyKV.Key) async throws {
        try await set(data: JSONEncoder().encode(value), for: key)
    }

    public func set(data: Data, for key: TinyKV.Key) async throws {
        bufferQueue.sync(flags: .barrier) {
            self.buffer[BufferedKey(key)] = data
        }
    }

    public func flush() async throws {
        throw TinyBufferedKVError.notImplemented
    }

    public func getData(for key: TinyKV.Key) async throws -> Data {
        if let data = bufferQueue.sync(execute: { self.buffer[BufferedKey(key)] }) {
            return data
        }
        return try await tinyKV.getData(for: key)
    }

    public func getDatas(for rangeKey: TinyKV.RangeKey, acend: Bool = true) async throws -> [Data] {
        return try await tinyKV.getDatas(for: rangeKey, acend: acend)
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
