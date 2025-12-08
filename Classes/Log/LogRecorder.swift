//
//  FileLog.swift
//  Pods
//
//  Created by ray on 2025/10/12.
//

import Foundation

// MARK: - 使用示例
/*
 // 示例 1：记录字符串内容
 LogRecorder.shared.saveLog(content: "应用启动", key: "app_lifecycle")
 
 // 示例 2：记录自定义对象
 struct UserAction: Codable {
     let action: String
     let userId: Int
 }
 let action = UserAction(action: "登录", userId: 12345)
 LogRecorder.shared.saveLog(content: action, key: "user_action")
 
 // 示例 3：使用时间间隔限制（相同 key 至少间隔 60 秒）
 LogRecorder.shared.saveLog(content: "按钮点击", key: "button_tap", minIntervalBetweenSameKey: 60)
 
 // 获取当前日志文件路径
 if let logPath = LogRecorder.shared.getCurrentLogFilePath() {
     print("日志文件路径：\(logPath)")
 }
 */


/// 日志记录类
public class LogRecorder {
    
    // MARK: - 单例
    public static let shared = LogRecorder(logNamePrefix: "global_shared")
    
    // MARK: - 私有属性
    private let logNamePrefix: String
    private let fileManager = FileManager.default
    private var logFileURL: URL?
    private let dateFormatter: DateFormatter
    private let queue = DispatchQueue(label: "com.logrecorder.queue", qos: .utility)
    private var lastWriteTimestamps: [String: Date] = [:]
    private var logCount = 0
    
    // MARK: - 初始化
    public init(logNamePrefix: String) {
        self.logNamePrefix = logNamePrefix
        dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd HH:mm:ss ZZZZ"
        dateFormatter.locale = Locale(identifier: "en_US_POSIX")
        dateFormatter.timeZone = TimeZone.current
    }
    
    // MARK: - 公开方法
    
    /// 保存日志
    /// - Parameters:
    ///   - content: 需要记录的内容（任何遵循 Encodable 的类型）
    ///   - key: 日志的键
    ///   - minIntervalBetweenSameKey: 相同 key 写入的最小时间间隔，nil 表示不限制
    public func saveLog<T: Encodable>(content: T, key: String, minIntervalBetweenSameKey: TimeInterval? = nil) {
        queue.async { [weak self] in
            guard let self = self else { return }
            
            // 检查时间间隔限制
            if let minInterval = minIntervalBetweenSameKey {
                if let lastWriteTime = self.lastWriteTimestamps[key] {
                    let timeInterval = Date().timeIntervalSince(lastWriteTime)
                    if timeInterval < minInterval {
                        print("日志写入被跳过：key '\(key)' 距离上次写入时间不足 \(minInterval) 秒")
                        return
                    }
                }
            }
            
            // 获取或创建日志文件
            guard let fileURL = self.getOrCreateLogFile() else {
                print("无法创建日志文件")
                return
            }
            
            // 构建日志条目
            let now = Date()
            let logEntry = LogEntry(key: key, date: self.dateFormatter.string(from: now), timestamp: Int(now.timeIntervalSince1970), content: content, log_index: logCount)
            
            // 将日志条目转换为 JSON
            guard let jsonData = self.encodeLogEntry(logEntry) else {
                print("日志编码失败")
                return
            }
            
            // 写入文件
            if self.writeToFile(data: jsonData, fileURL: fileURL) {
                // 更新最后写入时间
                self.lastWriteTimestamps[key] = Date()
                logCount += 1
            }
        }
    }
    
    // MARK: - 私有方法
    
    /// 获取或创建日志文件
    public func getOrCreateLogFile() -> URL? {
        // 如果已经有日志文件，直接返回
        if let existingURL = logFileURL {
            return existingURL
        }
        
        // 获取 Documents 目录
        guard let documentsDirectory = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first else {
            print("无法获取 Documents 目录")
            return nil
        }
        
        // 创建文件名（使用当前时间，精确到秒）
        let fileNameFormatter = DateFormatter()
        fileNameFormatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        fileNameFormatter.locale = Locale(identifier: "en_US_POSIX")
        fileNameFormatter.timeZone = TimeZone.current
        
        let fileName = "\(fileNameFormatter.string(from: Date())).json"
        let fileURL = documentsDirectory.appendingPathComponent("RYKitLogs\(logNamePrefix)\(fileName)")
        
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

// MARK: - 日志条目模型
private struct LogEntry<T: Encodable>: Encodable {
    let key: String
    let date: String
    let timestamp: Int
    let content: T
    let log_index: Int
}

