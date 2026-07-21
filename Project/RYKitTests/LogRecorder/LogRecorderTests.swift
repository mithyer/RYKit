//
//  LogRecorderTests.swift
//  RYKitTests
//

import XCTest
#if SWIFT_PACKAGE
@testable import RYKitCore
#else
@testable import RYKit
#endif

/// Tests the observable filesystem behavior of LogRecorder initialization.
final class LogRecorderTests: XCTestCase {

    /// Verifies that initialization creates the configured log directory.
    func test_initialization_createsLogDirectory() throws {
        let logDirectoryURL = try XCTUnwrap(
            FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first?
                .appendingPathComponent("RYKitLogs", isDirectory: true)
        )

        _ = LogRecorder(logNamePrefix: "test-\(UUID().uuidString)")

        var isDirectory: ObjCBool = false
        XCTAssertTrue(FileManager.default.fileExists(atPath: logDirectoryURL.path, isDirectory: &isDirectory))
        XCTAssertTrue(isDirectory.boolValue)
    }

    /// Verifies that a log remains in memory before the configured threshold is reached.
    func test_logBelowBufferSize_isNotWrittenToFile() throws {
        let recorder = LogRecorder(logNamePrefix: "buffered-\(UUID().uuidString)", bufferSize: 2)
        let fileURL = try XCTUnwrap(recorder.getOrCreateLogFile())
        defer { try? FileManager.default.removeItem(at: fileURL) }
        let initialData = try Data(contentsOf: fileURL)

        recorder.printAndSaveLog(content: "first", style: .plainText, key: "buffered")
        Thread.sleep(forTimeInterval: 0.2)

        XCTAssertEqual(try Data(contentsOf: fileURL), initialData)
    }

    /// Verifies that reaching the configured threshold writes the buffered entries as one batch.
    func test_bufferSizeReached_writesAllBufferedLogs() throws {
        let recorder = LogRecorder(logNamePrefix: "auto-flush-\(UUID().uuidString)", bufferSize: 2)
        let fileURL = try XCTUnwrap(recorder.getOrCreateLogFile())
        defer { try? FileManager.default.removeItem(at: fileURL) }

        recorder.printAndSaveLog(content: "first", style: .plainText, key: "auto-flush")
        recorder.printAndSaveLog(content: "second", style: .plainText, key: "auto-flush")

        let deadline = Date().addingTimeInterval(1)
        var contents = ""
        while Date() < deadline {
            contents = try String(contentsOf: fileURL, encoding: .utf8)
            if contents.contains("first") && contents.contains("second") {
                break
            }
            Thread.sleep(forTimeInterval: 0.01)
        }
        XCTAssertTrue(contents.contains("first") && contents.contains("second"))
    }

    /// Verifies that manual flush writes pending entries before returning.
    func test_flush_writesPendingLogsImmediately() throws {
        let recorder = LogRecorder(logNamePrefix: "manual-flush-\(UUID().uuidString)", bufferSize: 10)
        let fileURL = try XCTUnwrap(recorder.getOrCreateLogFile())
        defer { try? FileManager.default.removeItem(at: fileURL) }

        recorder.printAndSaveLog(content: "pending", style: .plainText, key: "manual-flush")
        recorder.flush()

        let contents = try String(contentsOf: fileURL, encoding: .utf8)
        XCTAssertTrue(contents.contains("pending"))
    }
}
