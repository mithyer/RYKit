//
//  TinyBufferedKV.swift
//  RYKit
//
//  Created by Codex on 2026/3/26.
//

import Foundation

/// A buffered key-value store that batches writes in memory and flushes to `TinyKV`.
///
/// Flush is triggered either by buffer limits or by a debounced timer after writes.
public final class TinyBufferedKV: TinyKVReadWritable, TinyKVFlushable {

    /// Runtime limits and flush behavior for `TinyBufferedKV`.
    public struct Config {
        /// Maximum number of buffered records before forcing a flush.
        public let maxBufferedItems: Int
        /// Maximum total buffered payload size in bytes before forcing a flush.
        public let maxBufferedBytes: Int
        /// Debounce interval in seconds for timer-based flush after writes.
        /// Set to `0` to disable timer-based flushing.
        public let flushInterval: TimeInterval

        /// Creates a configuration for `TinyBufferedKV`.
        /// - Parameters:
        ///   - maxBufferedItems: Maximum in-memory record count before auto flush.
        ///   - maxBufferedBytes: Maximum in-memory byte size before auto flush.
        ///   - flushInterval: Debounce delay in seconds for timer-based flush.
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

    /// Creates a buffered store on top of `TinyKV`.
    /// - Parameters:
    ///   - dbName: SQLite database name.
    ///   - tableName: Target table name.
    ///   - config: Buffer and flush strategy.
    public init(dbName: String, tableName: String, config: Config = .init()) {
        self.config = config
        self.storage = TinyKV(dbName: dbName, tableName: tableName)
        // Timer is not started at init; debounce scheduling is write-driven.
    }

    deinit {
        cancelFlushTimer()
    }

    /// Encodes and buffers a value for the given key.
    ///
    /// The write is persisted later on `flush()`, on debounce timeout, or when limits are exceeded.
    public func set<T: Encodable>(value: T, for key: TinyKVKey) async throws {
        try await set(data: JSONEncoder().encode(value), for: key)
    }

    /// Buffers raw payload data for the given key.
    ///
    /// If buffer limits are exceeded, this call triggers an immediate flush.
    public func set(data: Data, for key: TinyKVKey) async throws {
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
        } else {
            scheduleDebouncedFlushIfNeeded()
        }
    }

    /// Flushes all currently buffered entries to persistent storage.
    ///
    /// This is an explicit flush and propagates write errors to the caller.
    public func flush() async throws {
        cancelFlushTimer()

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
            let persistenceKey = tinyTinyKVKey(for: entry.key)
            try await storage.set(data: entry.data, for: persistenceKey)
        }
    }

    /// Returns raw data for a key.
    ///
    /// Reads from in-memory buffer first, then falls back to `TinyKV` storage.
    public func getData(for key: TinyKVKey) async throws -> Data {
        let bufferKey = canonicalKey(for: key)
        if let data = queue.sync(execute: { buffer[bufferKey] }) {
            return data
        }
        return try await storage.getData(for: key)
    }

    /// Flushes pending writes and returns raw data for a range query.
    public func getDatas(for rangeKey: TinyKVQueryKey, acend: Bool = true) async throws -> [Data] {
        try await flush()
        return try await storage.getDatas(for: rangeKey, acend: acend)
    }

    /// Returns a decoded value for a single key.
    public func getValue<T: Decodable>(for key: TinyKVKey) async throws -> T {
        let data = try await getData(for: key)
        return try JSONDecoder().decode(T.self, from: data)
    }

    /// Flushes pending writes and returns decoded values for a range query.
    public func getValues<T: Decodable>(for rangeKey: TinyKVQueryKey, acend: Bool = true) async throws -> [T] {
        let datas = try await getDatas(for: rangeKey, acend: acend)
        let decoder = JSONDecoder()
        return try datas.map { try decoder.decode(T.self, from: $0) }
    }

    private func canonicalKey(for key: TinyKVKey) -> BufferKey {
        switch key {
        case .string(let value):
            return .string(value)
        case .int(let value):
            return .int(value)
        }
    }

    private func tinyTinyKVKey(for bufferKey: BufferKey) -> TinyKVKey {
        switch bufferKey {
        case .string(let value):
            return .string(value)
        case .int(let value):
            return .int(value)
        }
    }

    private func scheduleDebouncedFlushIfNeeded() {
        guard config.flushInterval > 0 else {
            return
        }

        timerQueue.sync {
            flushTimer?.setEventHandler {}
            flushTimer?.cancel()

            let timer = DispatchSource.makeTimerSource(queue: timerQueue)
            timer.schedule(deadline: .now() + config.flushInterval)
            timer.setEventHandler { [weak self] in
                guard let self else { return }
                Task { [weak self] in
                    guard let self else { return }
                    do {
                        try await self.flush()
                    } catch {
                        print("TinyBufferedKV debounced flush error: \(error)")
                    }
                }
            }
            timer.resume()
            flushTimer = timer
        }
    }

    private func cancelFlushTimer() {
        timerQueue.sync {
            flushTimer?.setEventHandler {}
            flushTimer?.cancel()
            flushTimer = nil
        }
    }
}
