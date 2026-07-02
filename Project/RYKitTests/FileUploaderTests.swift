//
//  FileUploaderTests.swift
//  RYKitTests
//
//  Created by Codex on 2026/7/1.
//

import Combine
import Foundation
import XCTest
@testable import RYKit

final class FileUploaderTests: XCTestCase {

    override func tearDown() {
        UploadURLProtocolStub.requestHandler = nil
        super.tearDown()
    }

    func test_init_setsNotStartedState() {
        let uploader = makeUploader()

        guard case .notStarted = uploader.state else {
            XCTFail("Expected notStarted, got \(uploader.state)")
            return
        }
    }

    func test_init_exposesUploadConfiguration() {
        let url = URL(string: "https://example.com/upload")!
        let uploader = HttpRequest.FileUploader(
            fileName: "avatar.png",
            mimeType: "image/png",
            to: url,
            fieldName: "avatar",
            method: .OTHER(method: "PUT"),
            headers: ["Authorization": "Bearer token"]
        )

        XCTAssertEqual(uploader.fileName, "avatar.png")
        XCTAssertEqual(uploader.mimeType, "image/png")
        XCTAssertEqual(uploader.url, url)
        XCTAssertEqual(uploader.fieldName, "avatar")
        guard case .OTHER(let method) = uploader.method else {
            XCTFail("Expected custom method")
            return
        }
        XCTAssertEqual(method, "PUT")
        XCTAssertEqual(uploader.headers, ["Authorization": "Bearer token"])
    }

    func test_start_whenAlreadyStartedThrowsAlreadyStarted() async {
        let uploader = makeUploader()
        let firstStart = Task {
            try await uploader.start(data: Data("file".utf8))
        }

        await waitUntilStarted(uploader)

        do {
            _ = try await uploader.start(data: Data("file".utf8))
            XCTFail("Expected alreadyStarted error")
        } catch HttpRequest.FileUploader.UploadError.alreadyStarted {
        } catch {
            XCTFail("Expected alreadyStarted, got \(error)")
        }

        uploader.cancel()
        _ = try? await firstStart.value
    }

    func test_closureStart_whenAlreadyStartedCompletesWithAlreadyStarted() async {
        let uploader = makeUploader()
        let firstStart = Task {
            try await uploader.start(data: Data("file".utf8))
        }
        let completed = expectation(description: "closure completion")

        await waitUntilStarted(uploader)
        uploader.start(data: Data("file".utf8)) { result in
            do {
                _ = try result.get()
                XCTFail("Expected alreadyStarted error")
            } catch HttpRequest.FileUploader.UploadError.alreadyStarted {
            } catch {
                XCTFail("Expected alreadyStarted, got \(error)")
            }
            completed.fulfill()
        }

        await fulfillment(of: [completed], timeout: 1)
        uploader.cancel()
        _ = try? await firstStart.value
    }

    func test_closureStart_successCompletesWithResponseData() async {
        UploadURLProtocolStub.requestHandler = { protocolStub in
            protocolStub.complete(statusCode: 200, data: Data("ok".utf8))
        }
        let uploader = makeUploader()
        let completed = expectation(description: "closure completion")

        uploader.start(data: Data("file".utf8)) { result in
            XCTAssertEqual(try? result.get(), Data("ok".utf8))
            completed.fulfill()
        }

        await fulfillment(of: [completed], timeout: 1)
    }

    func test_cancel_afterStartEndsWithFailure() async {
        let uploader = makeUploader()
        let started = Task {
            try await uploader.start(data: Data("file".utf8))
        }

        await waitUntilStarted(uploader)
        uploader.cancel()

        do {
            _ = try await started.value
            XCTFail("Expected cancellation failure")
        } catch let error as URLError {
            XCTAssertEqual(error.code, .cancelled)
            guard case .ended(.failure) = uploader.state else {
                XCTFail("Expected failure end state, got \(uploader.state)")
                return
            }
        } catch {
            XCTFail("Expected cancelled URLError, got \(error)")
        }
    }

    func test_statePublisher_emitsProgressUpdates() {
        let uploader = makeUploader()
        var progressValues: [Double] = []
        let cancellable = uploader.statePublisher.sink { state in
            if case .uploading(let progress) = state {
                progressValues.append(progress)
            }
        }
        let session = URLSession(configuration: .ephemeral)
        let task = session.dataTask(with: URL(string: "https://example.com/upload")!)

        uploader.urlSession(
            session,
            task: task,
            didSendBodyData: 25,
            totalBytesSent: 25,
            totalBytesExpectedToSend: 100
        )

        XCTAssertEqual(progressValues, [0.25])
        guard case .uploading(let progress) = uploader.state else {
            XCTFail("Expected uploading state, got \(uploader.state)")
            return
        }
        XCTAssertEqual(progress, 0.25)
        session.invalidateAndCancel()
        _ = cancellable
    }

    // Verifies state publication never holds the internal lock while subscribers synchronously read state.
    func test_statePublisher_allowsSubscriberToReadStateDuringUpload() async {
        UploadURLProtocolStub.requestHandler = { protocolStub in
            protocolStub.complete(statusCode: 200, data: Data("ok".utf8))
        }
        let uploader = makeUploader()
        let completed = expectation(description: "upload completed")
        let cancellable = uploader.statePublisher.sink { _ in
            _ = uploader.state
        }

        Task {
            do {
                let data = try await uploader.start(data: Data("file".utf8))
                XCTAssertEqual(data, Data("ok".utf8))
                completed.fulfill()
            } catch {
                XCTFail("Expected upload success, got \(error)")
            }
        }

        await fulfillment(of: [completed], timeout: 1)
        _ = cancellable
    }

    func test_start_sanitizesMultipartHeaderValuesAndPreservesBoundaryContentType() async throws {
        var capturedRequest: URLRequest?
        UploadURLProtocolStub.requestHandler = { protocolStub in
            capturedRequest = protocolStub.request
            protocolStub.complete(statusCode: 200, data: Data())
        }
        let uploader = HttpRequest.FileUploader(
            fileName: "avatar\";\r\nX-Injected: yes.png",
            mimeType: "image/png",
            to: URL(string: "https://example.com/upload")!,
            fieldName: "file\";\r\nbad",
            headers: [
                "Content-Type": "text/plain",
                "X-Trace": "trace-id"
            ],
            configuration: Self.stubbedConfiguration()
        )
        let capturedBody = uploader.makeMultipartBody(
            fileData: Data("file".utf8),
            boundary: "TestBoundary"
        )

        _ = try await uploader.start(data: Data("file".utf8))

        let request = try XCTUnwrap(capturedRequest)
        XCTAssertEqual(request.value(forHTTPHeaderField: "X-Trace"), "trace-id")
        XCTAssertTrue(request.value(forHTTPHeaderField: "Content-Type")?.hasPrefix("multipart/form-data; boundary=") == true)

        let body = try XCTUnwrap(String(data: capturedBody, encoding: .utf8))
        XCTAssertTrue(body.contains("Content-Disposition:"), body)
        let contentDisposition = try XCTUnwrap(body
            .components(separatedBy: .newlines)
            .first { $0.contains("Content-Disposition:") })
        XCTAssertEqual(
            contentDisposition,
            "Content-Disposition: form-data; name=\"file%22%3B%0D%0Abad\"; filename=\"avatar%22%3B%0D%0AX-Injected: yes.png\""
        )
        XCTAssertFalse(body.contains("\r\nX-Injected"))
        XCTAssertFalse(body.contains("\r\nbad"))
        XCTAssertTrue(contentDisposition.contains("%22"))
        XCTAssertTrue(contentDisposition.contains("%3B"))
        XCTAssertTrue(contentDisposition.contains("%0D%0A"))
    }

    func test_makeMultipartBody_includesAdditionalTextFieldsBeforeFilePart() throws {
        let uploader = HttpRequest.FileUploader(
            fileName: "avatar.png",
            mimeType: "image/png",
            to: URL(string: "https://example.com/upload")!,
            fieldName: "file",
            additionalTextFields: [
                "album": "mobile",
                "description": "Summer upload"
            ],
            configuration: Self.stubbedConfiguration()
        )

        let body = try XCTUnwrap(String(
            data: uploader.makeMultipartBody(fileData: Data("image-bytes".utf8), boundary: "TestBoundary"),
            encoding: .utf8
        ))
        let albumHeader = "Content-Disposition: form-data; name=\"album\""
        let descriptionHeader = "Content-Disposition: form-data; name=\"description\""
        let fileHeader = "Content-Disposition: form-data; name=\"file\"; filename=\"avatar.png\""
        guard let albumRange = body.range(of: albumHeader),
              let descriptionRange = body.range(of: descriptionHeader),
              let fileRange = body.range(of: fileHeader) else {
            XCTFail(body)
            return
        }

        XCTAssertLessThan(albumRange.lowerBound, fileRange.lowerBound, body)
        XCTAssertLessThan(descriptionRange.lowerBound, fileRange.lowerBound, body)
        XCTAssertTrue(body.contains("\r\n\r\nmobile\r\n"), body)
        XCTAssertTrue(body.contains("\r\n\r\nSummer upload\r\n"), body)
    }

    func test_makeMultipartBody_percentEncodesLiteralPercentSignsInHeaderValues() throws {
        let uploader = HttpRequest.FileUploader(
            fileName: "100%complete.png",
            mimeType: "image/png",
            to: URL(string: "https://example.com/upload")!,
            fieldName: "file%name",
            configuration: Self.stubbedConfiguration()
        )

        let body = try XCTUnwrap(String(
            data: uploader.makeMultipartBody(fileData: Data("file".utf8), boundary: "TestBoundary"),
            encoding: .utf8
        ))
        let contentDisposition = try XCTUnwrap(body
            .components(separatedBy: .newlines)
            .first { $0.contains("Content-Disposition:") })

        XCTAssertEqual(
            contentDisposition,
            "Content-Disposition: form-data; name=\"file%25name\"; filename=\"100%25complete.png\""
        )
        XCTAssertFalse(contentDisposition.contains("file%name"))
        XCTAssertFalse(contentDisposition.contains("100%complete.png"))
    }

    func test_start_returnsRawDataWhenResponseBodyLooksLikeBusinessWrapper() async throws {
        let responseData = Data(#"{"code":401,"message":"Denied","data":null}"#.utf8)
        UploadURLProtocolStub.requestHandler = { protocolStub in
            protocolStub.complete(
                statusCode: 200,
                data: responseData
            )
        }
        let uploader = makeUploader()

        let data = try await uploader.start(data: Data("file".utf8))

        XCTAssertEqual(data, responseData)
        guard case .ended(.success(let stateData)) = uploader.state else {
            XCTFail("Expected success end state, got \(uploader.state)")
            return
        }
        XCTAssertEqual(stateData, responseData)
    }

    func test_start_byDefaultRejectsNon2xxStatusCode() async {
        UploadURLProtocolStub.requestHandler = { protocolStub in
            protocolStub.complete(statusCode: 400, data: Data("bad request".utf8))
        }
        let uploader = makeUploader()

        do {
            _ = try await uploader.start(data: Data("file".utf8))
            XCTFail("Expected bad server response")
        } catch let error as URLError {
            XCTAssertEqual(error.code, .badServerResponse)
        } catch {
            XCTFail("Expected badServerResponse, got \(error)")
        }
    }

    func test_start_acceptsConfiguredSingleStatusCode() async throws {
        let responseData = Data("bad request body".utf8)
        UploadURLProtocolStub.requestHandler = { protocolStub in
            protocolStub.complete(statusCode: 400, data: responseData)
        }
        let uploader = makeUploader(acceptedStatusCodes: [.single(400)])

        let data = try await uploader.start(data: Data("file".utf8))

        XCTAssertEqual(data, responseData)
    }

    func test_start_acceptsConfiguredStatusCodeRange() async throws {
        let responseData = Data("unprocessable body".utf8)
        UploadURLProtocolStub.requestHandler = { protocolStub in
            protocolStub.complete(statusCode: 422, data: responseData)
        }
        let uploader = makeUploader(acceptedStatusCodes: [.range(400..<500)])

        let data = try await uploader.start(data: Data("file".utf8))

        XCTAssertEqual(data, responseData)
    }

    func test_start_withNilAcceptedStatusCodesAllowsAnyHTTPStatusCode() async throws {
        let responseData = Data("server body".utf8)
        UploadURLProtocolStub.requestHandler = { protocolStub in
            protocolStub.complete(statusCode: 503, data: responseData)
        }
        let uploader = makeUploader(acceptedStatusCodes: nil)

        let data = try await uploader.start(data: Data("file".utf8))

        XCTAssertEqual(data, responseData)
    }

    private func makeUploader(
        acceptedStatusCodes: [HttpRequest.FileUploader.AcceptedStatusCode]? = [.range(200..<300)]
    ) -> HttpRequest.FileUploader {
        HttpRequest.FileUploader(
            fileName: "file.txt",
            mimeType: "text/plain",
            to: URL(string: "https://example.com/upload")!,
            fieldName: "file",
            acceptedStatusCodes: acceptedStatusCodes,
            configuration: Self.stubbedConfiguration()
        )
    }

    private static func stubbedConfiguration() -> URLSessionConfiguration {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [UploadURLProtocolStub.self]
        return configuration
    }

    private func waitUntilStarted(
        _ uploader: HttpRequest.FileUploader,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async {
        for _ in 0..<100 {
            if case .notStarted = uploader.state {
                await Task.yield()
            } else {
                return
            }
        }
        XCTFail("uploader never started", file: file, line: line)
    }
}

private final class UploadURLProtocolStub: URLProtocol {

    static var requestHandler: ((UploadURLProtocolStub) -> Void)?

    var requestBody: Data {
        guard let stream = request.httpBodyStream else {
            return request.httpBody ?? Data()
        }

        stream.open()
        defer { stream.close() }

        var data = Data()
        let bufferSize = 1024
        var buffer = [UInt8](repeating: 0, count: bufferSize)
        while true {
            let readCount = stream.read(&buffer, maxLength: bufferSize)
            if readCount <= 0 {
                break
            }
            data.append(buffer, count: readCount)
        }
        return data
    }

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        Self.requestHandler?(self)
    }

    override func stopLoading() {
        client?.urlProtocol(self, didFailWithError: URLError(.cancelled))
    }

    func complete(statusCode: Int, data: Data) {
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: statusCode,
            httpVersion: nil,
            headerFields: nil
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }
}
