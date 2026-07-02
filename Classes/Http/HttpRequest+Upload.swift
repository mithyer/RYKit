//
//  HttpRequest+Upload.swift
//  RYKit
//
//  Created by mao rui on 2026/7/1.
//

import Combine
import Foundation

extension HttpRequest {
    /// Uploads one multipart file request and publishes its lifecycle state.
    public final class FileUploader: NSObject {

        /// File name sent in the multipart `Content-Disposition` header.
        public private(set) var fileName: String
        /// MIME type sent in the multipart file part.
        public private(set) var mimeType: String
        /// Destination URL for the upload request.
        public private(set) var url: URL
        /// Multipart form field name that contains the uploaded file.
        public private(set) var fieldName: String
        /// HTTP method used for the upload request.
        public private(set) var method: HttpRequest.Method
        /// Additional request headers applied before the multipart `Content-Type`.
        public private(set) var headers: [String: String]?
        /// Additional text fields sent before the file part in the multipart body.
        public private(set) var additionalTextFields: [String: String]
        /// HTTP status codes accepted as a successful upload. `nil` accepts every HTTP status code.
        public private(set) var acceptedStatusCodes: [AcceptedStatusCode]?
        private let configuration: URLSessionConfiguration
        private let lock = NSLock()

        /// Current upload state.
        public var state: State {
            lock.lock()
            defer { lock.unlock() }
            return currentState
        }

        /// Publisher that emits upload state changes.
        public var statePublisher: Published<State>.Publisher {
            $publishedState
        }

        @Published private var publishedState: State = .notStarted
        // Stores state under lock; @Published is only used for unlocked synchronous notification.
        private var currentState: State = .notStarted
        private var responseData = Data()
        private var session: URLSession?
        private var task: URLSessionTask?
        private var continuation: CheckedContinuation<Data, Error>?
        private var cancelRequested = false

        /// Creates a single-use file uploader.
        /// - Parameters:
        ///   - fileName: File name sent in the multipart `Content-Disposition` header.
        ///   - mimeType: MIME type sent in the multipart file part.
        ///   - url: Destination URL for the upload request.
        ///   - fieldName: Multipart form field name that contains the uploaded file.
        ///   - method: HTTP method used for the upload request. Defaults to `POST`.
        ///   - headers: Additional request headers. A caller-supplied `Content-Type` is ignored so the multipart boundary stays valid.
        ///   - additionalTextFields: Extra text fields sent before the file part.
        ///   - acceptedStatusCodes: HTTP status codes treated as success. Pass `nil` to accept every HTTP status code.
        ///   - configuration: URL session configuration used to create the upload session. Pass `nil` to use `.default`.
        public init(
            fileName: String,
            mimeType: String,
            to url: URL,
            fieldName: String,
            method: HttpRequest.Method = .POST,
            headers: [String: String]? = nil,
            additionalTextFields: [String: String] = [:],
            acceptedStatusCodes: [AcceptedStatusCode]? = [.range(200..<300)],
            configuration: URLSessionConfiguration? = nil
        ) {
            self.fileName = fileName
            self.mimeType = mimeType
            self.url = url
            self.fieldName = fieldName
            self.method = method
            self.headers = headers
            self.additionalTextFields = additionalTextFields
            self.acceptedStatusCodes = acceptedStatusCodes
            self.configuration = configuration ?? .default
            super.init()
        }
    }
}

extension HttpRequest.FileUploader: URLSessionTaskDelegate, URLSessionDataDelegate {

    /// HTTP status code matcher used to decide whether a completed upload is successful.
    public enum AcceptedStatusCode: Equatable {
        /// Accepts one exact HTTP status code.
        case single(Int)
        /// Accepts all HTTP status codes in the half-open range.
        case range(Range<Int>)

        func contains(_ statusCode: Int) -> Bool {
            switch self {
            case .single(let acceptedCode):
                return acceptedCode == statusCode
            case .range(let acceptedRange):
                return acceptedRange.contains(statusCode)
            }
        }
    }

    /// Upload lifecycle state.
    public enum State: CustomStringConvertible {
        /// The uploader has not started a task yet.
        case notStarted
        /// The upload task is running with a progress value from `0` to `1`.
        case uploading(progress: Double)
        /// The upload task has finished with response data or an error.
        case ended(Result<Data, Error>)

        /// Human-readable state text for debugging and test diagnostics.
        public var description: String {
            switch self {
            case .notStarted:
                return "notStarted"
            case .uploading(let progress):
                return "uploading(progress: \(progress))"
            case .ended(.success):
                return "ended(success)"
            case .ended(.failure(let error)):
                return "ended(failure: \(error))"
            }
        }
    }

    /// Errors produced by the uploader before a network response is available.
    public enum UploadError: Error, Equatable {
        /// A caller attempted to start an uploader that has already left `State.notStarted`.
        case alreadyStarted
    }

    /// Starts the upload and returns the response data when the request completes with an accepted HTTP status.
    /// - Parameter fileData: Raw file data to send as the multipart body.
    /// - Returns: Response body data.
    /// - Throws: `UploadError.alreadyStarted`, URL loading errors, or `URLError.badServerResponse`.
    public func start(data fileData: Data) async throws -> Data {
        try markStarted()

        let boundary = "Boundary-\(UUID().uuidString)"
        var request = URLRequest(url: url)
        request.httpMethod = method.rawValue
        headers?.forEach { key, value in
            guard key.caseInsensitiveCompare("Content-Type") != .orderedSame else {
                return
            }
            request.setValue(value, forHTTPHeaderField: key)
        }
        request.setValue(
            "multipart/form-data; boundary=\(boundary)",
            forHTTPHeaderField: "Content-Type"
        )

        let body = makeMultipartBody(fileData: fileData, boundary: boundary)

        return try await withCheckedThrowingContinuation { continuation in
            let session = URLSession(
                configuration: configuration,
                delegate: self,
                delegateQueue: nil
            )
            let task = session.uploadTask(with: request, from: body)

            let shouldCancel: Bool
            lock.lock()
            self.responseData = Data()
            self.continuation = continuation
            self.session = session
            self.task = task
            shouldCancel = cancelRequested
            lock.unlock()

            guard !shouldCancel else {
                finish(with: .failure(URLError(.cancelled)))
                return
            }

            task.resume()
        }
    }

    /// Starts the upload and reports completion through a callback.
    /// - Parameters:
    ///   - fileData: Raw file data to send as the multipart body.
    ///   - completed: Completion called with response data or the upload error.
    public func start(data fileData: Data, completed: @escaping (Result<Data, Error>) -> Void) {
        Task {
            do {
                completed(.success(try await start(data: fileData)))
            } catch {
                completed(.failure(error))
            }
        }
    }

    /// Cancels the current upload task if it has started.
    public func cancel() {
        lock.lock()
        guard case .uploading = currentState else {
            lock.unlock()
            return
        }
        cancelRequested = true
        let task = task
        lock.unlock()

        if let task {
            task.cancel()
        }
    }

    private func markStarted() throws {
        let stateToPublish: State = .uploading(progress: 0)

        lock.lock()
        guard case .notStarted = currentState else {
            lock.unlock()
            throw UploadError.alreadyStarted
        }
        currentState = stateToPublish
        lock.unlock()

        // TEST:FileUploaderTests.swift[test_statePublisher_allowsSubscriberToReadStateDuringUpload]
        // @Published synchronously calls subscribers, so publish only after releasing the internal lock.
        publishedState = stateToPublish
    }

    func makeMultipartBody(fileData: Data, boundary: String) -> Data {
        var body = Data()
        let escapedFieldName = Self.escapedMultipartHeaderValue(fieldName)
        let escapedFileName = Self.escapedMultipartHeaderValue(fileName)
        for key in additionalTextFields.keys.sorted() {
            let escapedKey = Self.escapedMultipartHeaderValue(key)
            let value = additionalTextFields[key] ?? ""
            body.appendString("--\(boundary)\r\n")
            body.appendString("Content-Disposition: form-data; name=\"\(escapedKey)\"\r\n\r\n")
            body.appendString(value)
            body.appendString("\r\n")
        }
        body.appendString("--\(boundary)\r\n")
        body.appendString("Content-Disposition: form-data; name=\"\(escapedFieldName)\"; filename=\"\(escapedFileName)\"\r\n")
        body.appendString("Content-Type: \(mimeType)\r\n\r\n")
        body.append(fileData)
        body.appendString("\r\n")
        body.appendString("--\(boundary)--\r\n")
        return body
    }

    static func escapedMultipartHeaderValue(_ value: String) -> String {
        let unsafeScalars = CharacterSet(charactersIn: "\"\r\n;\\%")
        var escaped = ""
        for scalar in value.unicodeScalars {
            guard unsafeScalars.contains(scalar) else {
                escaped.unicodeScalars.append(scalar)
                continue
            }
            for byte in String(scalar).utf8 {
                escaped += String(format: "%%%02X", byte)
            }
        }
        return escaped
    }

    /// Receives upload progress from `URLSession`.
    public func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didSendBodyData bytesSent: Int64,
        totalBytesSent: Int64,
        totalBytesExpectedToSend: Int64
    ) {
        guard totalBytesExpectedToSend > 0 else { return }

        let progress = Double(totalBytesSent) / Double(totalBytesExpectedToSend)
        let stateToPublish: State = .uploading(progress: progress)
        lock.lock()
        currentState = stateToPublish
        lock.unlock()

        // TEST:FileUploaderTests.swift[test_statePublisher_allowsSubscriberToReadStateDuringUpload]
        // Progress callbacks may synchronously read state from subscribers; publish without holding the lock.
        publishedState = stateToPublish
    }

    /// Accumulates response body chunks from `URLSession`.
    public func urlSession(
        _ session: URLSession,
        dataTask: URLSessionDataTask,
        didReceive data: Data
    ) {
        lock.lock()
        responseData.append(data)
        lock.unlock()
    }

    /// Finalizes the upload when `URLSession` reports task completion.
    public func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didCompleteWithError error: Error?
    ) {
        let result: Result<Data, Error>
        if let error {
            result = .failure(error)
        } else if let httpResponse = task.response as? HTTPURLResponse,
                  accepts(statusCode: httpResponse.statusCode) {
            lock.lock()
            let data = responseData
            lock.unlock()
            result = .success(data)
        } else {
            result = .failure(URLError(.badServerResponse))
        }

        finish(with: result)
    }

    private func accepts(statusCode: Int) -> Bool {
        guard let acceptedStatusCodes else {
            return true
        }
        return acceptedStatusCodes.contains { $0.contains(statusCode) }
    }

    private func finish(with result: Result<Data, Error>) {
        let stateToPublish: State = .ended(result)

        lock.lock()
        guard let continuation else {
            lock.unlock()
            return
        }
        self.continuation = nil
        self.task = nil
        let session = self.session
        self.session = nil
        cancelRequested = false
        currentState = stateToPublish
        lock.unlock()

        // TEST:FileUploaderTests.swift[test_statePublisher_allowsSubscriberToReadStateDuringUpload]
        // End-state publication enters sinks synchronously; update currentState, unlock, then notify.
        publishedState = stateToPublish

        if result.isCancelled {
            session?.invalidateAndCancel()
        } else {
            session?.finishTasksAndInvalidate()
        }

        switch result {
        case .success(let data):
            continuation.resume(returning: data)
        case .failure(let error):
            continuation.resume(throwing: error)
        }
    }
}

private extension Result where Failure == Error {
    var isCancelled: Bool {
        guard case .failure(let error as URLError) = self else {
            return false
        }
        return error.code == .cancelled
    }
}

private extension Data {
    mutating func appendString(_ string: String) {
        if let data = string.data(using: .utf8) {
            append(data)
        }
    }
}
