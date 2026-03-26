//
//  TinyBufferedKV.swift
//  RYKit
//
//  Created by Codex on 2026/3/26.
//

import Foundation

public final class TinyBufferedKV {

    public struct Config {
        public let maxBufferedItems: Int
        public let maxBufferedBytes: Int
        public let flushInterval: TimeInterval

        public init(
            maxBufferedItems: Int = 200,
            maxBufferedBytes: Int = 1_048_576,
            flushInterval: TimeInterval = 0.5
        ) {
            precondition(maxBufferedItems > 0, "maxBufferedItems must be positive")
            precondition(maxBufferedBytes > 0, "maxBufferedBytes must be positive")
            precondition(flushInterval >= 0, "flushInterval cannot be negative")
            self.maxBufferedItems = maxBufferedItems
            self.maxBufferedBytes = maxBufferedBytes
            self.flushInterval = flushInterval
        }
    }

    public enum TinyBufferedKVError: Error {
        case notImplemented
    }

    private enum BufferKey: Hashable {
        case string(String)
        case int(UInt)
    }

    private typealias BufferEntry = (key: BufferKey, data: Data)

    private let config: Config
    private let storage: TinyKV
    private var buffer = [BufferKey: Data]()
    private var bufferedBytes = 0
    private let queue = DispatchQueue(label: "com.rykit.tinybufferedkv")
    private let timerQueue = DispatchQueue(label: "com.rykit.tinybufferedkv.timer")
    private var flushTimer: DispatchSourceTimer?

    public init(dbName: String, tableName: String, config: Config = .init()) {
        self.config = config
        self.storage = TinyKV(dbName: dbName, tableName: tableName)
        scheduleFlushTimer()
    }

    deinit {
        flushTimer?.setEventHandler {}
        flushTimer?.cancel()
    }

    public func set<T: Encodable>(value: T, for key: TinyKV.Key) async throws {
        try await set(data: JSONEncoder().encode(value), for: key)
    }

    public func set(data: Data, for key: TinyKV.Key) async throws {
        let bufferKey = canonicalKey(for: key)
        let shouldFlush = queue.sync { () -> Bool in
            let previousSize = buffer[bufferKey]?.count ?? 0
            buffer[bufferKey] = data
            bufferedBytes += data.count - previousSize

            let reachedItemLimit = buffer.count > config.maxBufferedItems
            let reachedByteLimit = bufferedBytes > config.maxBufferedBytes

            return reachedItemLimit || reachedByteLimit
        }

        if shouldFlush {
            try await flush()
        }
    }

    public func flush() async throws {
        let entries = queue.sync { () -> [BufferEntry] in
            guard !buffer.isEmpty else {
                return []
            }
            let snapshot = buffer.map { (key: $0.key, data: $0.value) }
            buffer.removeAll()
            bufferedBytes = 0
            return snapshot
        }

        guard !entries.isEmpty else {
            return
        }

        for entry in entries {
            let persistenceKey = tinyKVKey(for: entry.key)
            try await storage.set(data: entry.data, for: persistenceKey)
        }
    }

    public func getData(for key: TinyKV.Key) async throws -> Data {
        let bufferKey = canonicalKey(for: key)
        if let data = queue.sync(execute: { buffer[bufferKey] }) {
            return data
        }
        return try await storage.getData(for: key)
    }

    public func getDatas(for rangeKey: TinyKV.RangeKey, acend: Bool = true) async throws -> [Data] {
        throw TinyBufferedKVError.notImplemented
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

    private func tinyKVKey(for bufferKey: BufferKey) -> TinyKV.Key {
        switch bufferKey {
        case .string(let value):
            return .string(value)
        case .int(let value):
            return .int(value)
        }
    }

    private func scheduleFlushTimer() {
        guard config.flushInterval > 0 else {
            return
        }

        let timer = DispatchSource.makeTimerSource(queue: timerQueue)
        timer.schedule(deadline: .now() + config.flushInterval, repeating: config.flushInterval)
        timer.setEventHandler { [weak self] in
            guard let self = self else {
                return
            }
            Task { [weak self] in
                guard let self = self else {
                    return
                }
                do {
                    try await self.flush()
                } catch {
                    assertionFailure("TinyBufferedKV flush timer error: \(error)")
                }
            }
        }
        timer.resume()
        flushTimer = timer
    }
}
