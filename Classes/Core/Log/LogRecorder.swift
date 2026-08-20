//
//  FileLog.swift
//  Pods
//
//  Created by ray on 2025/10/12.
//

import Foundation
import os
// MARK: - Usage example
/*
 let recorder = LogRecorder(logNamePrefix: "app")
 recorder.printAndSaveLog(
     content: "App launched",
     style: .plainText,
     key: "app_lifecycle"
 )
 recorder.flush()

 if let logPath = recorder.getCurrentLogFilePath() {
     print("Log file: \(logPath)")
 }
*/


/// 日志记录类
public class LogRecorder {
    
    public enum LogStyle {
        case json, plainText
    }
        
    // MARK: - 私有属性
    private let logNamePrefix: String
    private let fileManager = FileManager.default
    /// Directory that stores all log files created by this recorder.
    private let logDirectoryURL: URL?
    private var logFileURL: URL?
    private let dateFormatter: DateFormatter
    private let queue = DispatchQueue(label: "com.logrecorder.queue", qos: .utility)
    /// Identifies the recorder queue so synchronous flushes cannot deadlock during reentrant calls.
    private let queueKey = DispatchSpecificKey<Void>()
    private var lastWriteTimestamps: [String: Date] = [:]
    private var logCount = 0
    /// Maximum number of pending entries retained before an automatic flush.
    private let bufferSize: Int
    /// Encoded log data waiting to be written to the current file.
    private var logBuffer = Data()
    /// Number of complete log entries currently stored in the buffer.
    private var bufferedLogCount = 0
    
    // MARK: - 初始化
    /// Creates a log recorder and prepares its directory in Documents.
    /// - Parameters:
    ///   - logNamePrefix: Prefix added to each log file name.
    ///   - bufferSize: Number of entries retained before they are written as one batch. Values below one are treated as one.
    /// TEST:LogRecorderTests[test_initialization_createsLogDirectory]
    /// TEST:LogRecorderTests[test_logBelowBufferSize_isNotWrittenToFile]
    public init(logNamePrefix: String, bufferSize: Int = 10000) {
        self.logNamePrefix = logNamePrefix
        self.bufferSize = max(1, bufferSize)
        logDirectoryURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first?
            .appendingPathComponent("RYKitLogs", isDirectory: true)
        dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS ZZZZZ"
        dateFormatter.locale = Locale(identifier: "en_US_POSIX")
        dateFormatter.timeZone = TimeZone.current
        createLogDirectoryIfNeeded()
        queue.setSpecific(key: queueKey, value: ())
    }
    
    // MARK: - 公开方法
    
    /// 保存日志
    /// - Parameters:
    ///   - content: 需要记录的内容（任何遵循 Encodable 的类型）
    ///   - key: 日志的键
    ///   - minIntervalBetweenSameKey: 相同 key 写入的最小时间间隔，nil 表示不限制
    /// TEST:LogRecorderTests[test_logBelowBufferSize_isNotWrittenToFile]
    /// TEST:LogRecorderTests[test_bufferSizeReached_writesAllBufferedLogs]
    public func printAndSaveLog<T: Encodable>(content: @escaping @autoclosure () -> T, style: LogStyle, key: String, minIntervalBetweenSameKey: TimeInterval? = nil, file: StaticString = #fileID, line: Int = #line, function: StaticString = #function) {
        let now = Date()
        queue.async { [weak self] in
            guard let self = self else { return }
            
            // 检查时间间隔限制
            if let minInterval = minIntervalBetweenSameKey {
                if let lastWriteTime = self.lastWriteTimestamps[key] {
                    let timeInterval = Date().timeIntervalSince(lastWriteTime)
                    if timeInterval < minInterval {
                        // 日志写入被跳过：key  距离上次写入时间不足 minInterval 秒
                        return
                    }
                }
            }
            
            // 构建日志条目
            let logEntry = LogEntry(key: key, date: self.dateFormatter.string(from: now), content: content(), log_index: logCount, from: "[\(file):\(line)] \(function)")
            
            var data: Data?
            if style == .json {
                data = self.encodeLogEntry(logEntry)
            }
            if let data {
                print(String(data: data, encoding: .utf8) ?? "")
            } else {
                let str = "\(logEntry)\n"
                data = str.data(using: .utf8)
                //print(str)
            }
            
            // Buffer the complete entry so a later flush can write the batch in one operation.
            guard let data else { return }
            self.logBuffer.append(data)
            self.bufferedLogCount += 1
            self.lastWriteTimestamps[key] = Date()
            self.logCount += 1

            // Write the accumulated data once the configured entry threshold is reached.
            if self.bufferedLogCount >= self.bufferSize {
                self.flushBufferedLogs()
            }
        }
    }

    /// Immediately writes all pending log entries and returns after the write attempt completes.
    /// TEST:LogRecorderTests[test_flush_writesPendingLogsImmediately]
    public func flush() {
        if DispatchQueue.getSpecific(key: queueKey) != nil {
            flushBufferedLogs()
            return
        }

        queue.sync {
            self.flushBufferedLogs()
        }
    }
    
    // MARK: - 私有方法

    /// Creates the log directory during recorder initialization.
    /// TEST:LogRecorderTests[test_initialization_createsLogDirectory]
    private func createLogDirectoryIfNeeded() {
        guard let logDirectoryURL else {
            print("无法获取 Documents 目录")
            return
        }

        do {
            try fileManager.createDirectory(at: logDirectoryURL, withIntermediateDirectories: true)
        } catch {
            print("创建日志目录失败：\(error)")
        }
    }

    /// Writes all pending entries in one file operation and retains them if writing fails.
    /// TEST:LogRecorderTests[test_bufferSizeReached_writesAllBufferedLogs]
    private func flushBufferedLogs() {
        guard !logBuffer.isEmpty,
              let fileURL = getOrCreateLogFile(),
              writeToFile(data: logBuffer, fileURL: fileURL) else {
            return
        }

        logBuffer.removeAll(keepingCapacity: true)
        bufferedLogCount = 0
    }
    
    /// 获取或创建日志文件
    public func getOrCreateLogFile() -> URL? {
        // 如果已经有日志文件，直接返回
        if let existingURL = logFileURL {
            return existingURL
        }
        
        // 获取日志目录
        guard let logDirectoryURL else {
            print("无法获取 Documents 目录")
            return nil
        }
        
        // 创建文件名（使用当前时间，精确到秒）
        let fileNameFormatter = DateFormatter()
        fileNameFormatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        fileNameFormatter.locale = Locale(identifier: "en_US_POSIX")
        fileNameFormatter.timeZone = TimeZone.current
        
        let fileName = "\(fileNameFormatter.string(from: Date())).log"
        let fileURL = logDirectoryURL.appendingPathComponent("\(logNamePrefix)_\(fileName)")
        
        // 如果文件不存在，创建文件并写入初始内容
        if !fileManager.fileExists(atPath: fileURL.path) {
            let initialContent = "[\n"
            do {
                try initialContent.write(to: fileURL, atomically: true, encoding: .utf8)
                print("日志文件已创建：\(fileURL.path)")
            } catch {
                print("创建日志文件失败：\(error)")
                return nil
            }
        }
        
        logFileURL = fileURL
        return fileURL
    }
    
    /// 编码日志条目为 JSON
    private func encodeLogEntry<T: Encodable>(_ entry: LogEntry<T>) -> Data? {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        
        do {
            let jsonData = try encoder.encode(entry)
            // 添加逗号和换行
            var dataWithComma = jsonData
            dataWithComma.append(contentsOf: ",\n".utf8)
            return dataWithComma
        } catch {
            print("编码日志失败：\(error)")
            return nil
        }
    }
    
    private var _fileHandle: FileHandle?
    private var fileHandle: FileHandle? {
        if nil == _fileHandle, let fileURL = getOrCreateLogFile() {
            _fileHandle = FileHandle(forWritingAtPath: fileURL.path)
        }
        return _fileHandle
    }
    
    /// 写入数据到文件
    private func writeToFile(data: Data, fileURL: URL) -> Bool {
        // 使用文件句柄追加内容
        if let fileHandle = self.fileHandle {
            fileHandle.seekToEndOfFile()
            fileHandle.write(data)
            return true
        } else {
            print("无法打开文件句柄")
            return false
        }
    }
    
    // MARK: - 辅助方法
    
    /// 获取当前日志文件路径
    public func getCurrentLogFilePath() -> String? {
        return logFileURL?.path
    }
    
    /// 清空所有记录的时间戳（用于测试或重置）
    public func resetTimestamps() {
        queue.async {
            self.lastWriteTimestamps.removeAll()
        }
    }
}

private let dateFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS ZZZZZ"
    return formatter
}()

// MARK: - 日志条目模型
private struct LogEntry<T: Encodable>: Encodable, CustomStringConvertible {
    let key: String
    let date: String
    let content: T
    let log_index: Int
    let from: String

    var description: String {
        "[\(key)] \(date)<\(log_index)> \(from): \(content)"
    }
}
