//
//  HttpRequestLoggingTests.swift
//  RYKitTests
//
//  Created by Codex on 2026/5/25.
//

import Foundation
import XCTest
@testable import RYKit

final class HttpRequestLoggingTests: XCTestCase {

    private struct EmptyEncodable: Encodable {}

    private struct ResponseModel: Decodable, Equatable {
        let value: String
    }

    private final class LogRecorder {
        private let lock = NSLock()
        private var storedMessages: [String] = []

        func append(_ message: String) {
            lock.lock()
            storedMessages.append(message)
            lock.unlock()
        }

        var messages: [String] {
            lock.lock()
            defer { lock.unlock() }
            return storedMessages
        }
    }

    override func tearDown() {
        URLProtocolStub.requestHandler = nil
        super.tearDown()
    }

    func test_responseLogsStartAndCompletionWithMatchingRequestId() {
        let payload = #"{"code":200,"data":{"value":"ok"}}"#.data(using: .utf8)!
        URLProtocolStub.requestHandler = { request in
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )!
            return (response, payload)
        }

        let recorder = LogRecorder()
        let request = makeRequest(path: "/logging", recorder: recorder)
        let completed = expectation(description: "response completed")

        request.response(ResponseModel.self, inMainThread: false) { result in
            XCTAssertEqual(try? result.get(), ResponseModel(value: "ok"))
            completed.fulfill()
        }

        wait(for: [completed], timeout: 1)

        let logs = recorder.messages
        guard let startLog = logs.first(where: { $0.contains("Request Start") }) else {
            XCTFail("Expected request start log")
            return
        }
        guard let successLog = logs.first(where: { $0.contains("Successed") }) else {
            XCTFail("Expected request completion log")
            return
        }

        XCTAssertTrue(startLog.contains("https://example.com/logging"))
        XCTAssertFalse(startLog.contains("Parameters"))
        XCTAssertFalse(startLog.contains("Request Headers"))

        let startToken = requestLogToken(in: startLog)
        XCTAssertNotNil(startToken)
        XCTAssertEqual(startToken, requestLogToken(in: successLog))
    }

    private func makeRequest(path: String, recorder: LogRecorder) -> HttpRequest {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [URLProtocolStub.self]
        let session = URLSession(configuration: configuration)
        let handlers = HttpRequest.Handlers(
            encryptModelHandler: { $0 },
            encryptParamsHandler: { _ in EmptyEncodable() },
            decryptDataHandler: { $0 },
            logSuccessHandler: { recorder.append($0) },
            logFailureHandler: { recorder.append($0) },
            customizeResponseErrorMessageHandler: nil,
            onResponseHttpErrorStatusCodeHandler: nil,
            onResponseBusinessErrorCodeHandler: nil
        )

        return HttpRequest(
            session: session,
            queue: DispatchQueue(label: "HttpRequestLoggingTests.queue"),
            baseURL: "https://example.com",
            method: .GET,
            path: path,
            params: nil,
            contentType: nil,
            requestStrategy: nil,
            baseHeaders: [:],
            handlers: handlers
        )
    }

    private func requestLogToken(in message: String) -> String? {
        guard let range = message.range(
            of: #"\[id:[0-9]+\]HttpRequest"#,
            options: .regularExpression
        ) else {
            return nil
        }
        return String(message[range])
    }
}

private final class URLProtocolStub: URLProtocol {

    static var requestHandler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        do {
            let (response, data) = try Self.requestHandler?(request) ?? {
                let response = HTTPURLResponse(
                    url: request.url!,
                    statusCode: 500,
                    httpVersion: nil,
                    headerFields: nil
                )!
                return (response, Data())
            }()
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}
