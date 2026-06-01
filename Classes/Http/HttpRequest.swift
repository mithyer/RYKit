//
//  HttpRequest.swift
//  TRSTradingClient
//
//  Created by ray on 2025/3/21.
//

import Combine
import Foundation
#if canImport(RYKitCore)
import RYKitCore
#endif
/// Builds a URL request, applies optional encryption/decryption, and decodes typed HTTP responses.
public final class HttpRequest {

    /// Supported request body content types.
    public enum ContentType: String {
        /// Encodes parameters as `application/x-www-form-urlencoded`.
        case applicationFormEncoded = "application/x-www-form-urlencoded"
        /// Encodes parameters as a JSON request body.
        case applicationJson = "application/json"
    }

    /// HTTP method abstraction used by this request wrapper.
    public enum Method {
        /// Standard GET request.
        case GET
        /// Standard POST request.
        case POST
        /// Custom HTTP method for APIs that need verbs outside the built-in cases.
        case OTHER(method: String)

        /// The concrete method string assigned to `URLRequest.httpMethod`.
        var rawValue: String {
            switch self {
            case .GET:
                "GET"
            case .POST:
                "POST"
            case .OTHER(let method):
                method
            }
        }
    }

    /// Parameter container that accepts either a dictionary or any `Encodable` model.
    public enum ParamsType: CustomStringConvertible {
        /// Dictionary parameters, usually used by dynamic request payloads.
        case dic([String: Any])
        /// Strongly typed parameters, encoded through `Encodable`.
        case model(any Encodable)

        /// Debug-friendly JSON description used in request logs.
        public var description: String {
            let prefix: String
            var data: Data?
            switch self {
            case .dic(let dictionary):
                prefix = "DICTIONARY ->\n"
                data = try? JSONSerialization.data(withJSONObject: dictionary)
            case .model(let encodable):
                prefix = "MODEL ->\n"
                data = try? JSONEncoder().encode(encodable)
            }
            guard let data, let text = String(data: data, encoding: .utf8) else {
                return "\(prefix) \(self)"
            }
            return "\(prefix) \(text)"
        }
    }

    /// Internal errors raised while preparing or parsing request data.
    public enum CodingError: Error {
        /// Parameter encryption failed before sending the request.
        case encrypt(String)
        /// Response decryption failed after receiving data.
        case decrypt(String)
        /// Request parameter encoding failed.
        case encoding(String)
        /// Response data decoding failed.
        case decoding(String)
    }

    /// Controls how repeated calls behave while another task is still active.
    public enum RequestStrategy {
        /// Rejects a new request when an older task is still running.
        case cancelIfRequesting
        /// Marks older responses as obsolete, optionally debouncing the newest task.
        case amendIfRequesting(debounceInterval: TimeInterval? = nil)
    }

    /// Custom hooks for encryption, decryption, logging, and error callbacks.
    public struct Handlers {
        /// Encrypts an `Encodable` parameter model before it is attached to the request.
        let encryptModelHandler: (_ model: any Encodable) throws -> any Encodable
        /// Encrypts dictionary parameters before they are attached to the request.
        let encryptParamsHandler: (_ params: [String: Any]) throws -> any Encodable
        /// Decrypts raw response data before decoding starts.
        let decryptDataHandler: (Data) throws -> Data
        /// Receives success-path log messages.
        let logSuccessHandler: ((String) -> Void)?
        /// Receives failure-path log messages.
        let logFailureHandler: ((String) -> Void)?
        /// Overrides the public error message returned to callers.
        let customizeResponseErrorMessageHandler: ((ResponseError) -> String)?
        /// Called on the main queue when the HTTP status code is not 2xx.
        let onResponseHttpErrorStatusCodeHandler: ((Int, ResponseErrorContext) -> Void)?
        /// Called on the main queue when the decoded business code is invalid.
        let onResponseBusinessErrorCodeHandler: ((Int, ResponseErrorContext) -> Void)?

        /// Stores all externally supplied request lifecycle handlers.
        /// - Parameters:
        ///   - encryptModelHandler: Encrypts an `Encodable` parameter model before it is attached to the request.
        ///   - encryptParamsHandler: Encrypts dictionary parameters before they are attached to the request.
        ///   - decryptDataHandler: Decrypts raw response data before decoding starts.
        ///   - logSuccessHandler: Receives success-path log messages.
        ///   - logFailureHandler: Receives failure-path log messages.
        ///   - customizeResponseErrorMessageHandler: Overrides the public error message returned to callers.
        ///   - onResponseHttpErrorStatusCodeHandler: Called when the HTTP status code is not 2xx.
        ///   - onResponseBusinessErrorCodeHandler: Called when the decoded business code is invalid.
        public init(encryptModelHandler: @escaping (_: any Encodable) throws -> any Encodable,
                    encryptParamsHandler: @escaping (_: [String : Any]) throws -> any Encodable,
                    decryptDataHandler: @escaping (Data) throws -> Data,
                    logSuccessHandler: ((String) -> Void)?,
                    logFailureHandler: ((String) -> Void)?,
                    customizeResponseErrorMessageHandler: ((ResponseError) -> String)?,
                    onResponseHttpErrorStatusCodeHandler: ((Int, ResponseErrorContext) -> Void)?,
                    onResponseBusinessErrorCodeHandler: ((Int, ResponseErrorContext) -> Void)?) {
            self.encryptModelHandler = encryptModelHandler
            self.encryptParamsHandler = encryptParamsHandler
            self.decryptDataHandler = decryptDataHandler
            self.logSuccessHandler = logSuccessHandler
            self.logFailureHandler = logFailureHandler
            self.customizeResponseErrorMessageHandler = customizeResponseErrorMessageHandler
            self.onResponseHttpErrorStatusCodeHandler = onResponseHttpErrorStatusCodeHandler
            self.onResponseBusinessErrorCodeHandler = onResponseBusinessErrorCodeHandler
        }
    }

    /// Describes where business status, message, and payload fields live in the response wrapper.
    public struct BusinessWrapperConfig {
        /// JSON key that contains the business status code.
        let codeKey: String
        /// JSON key that contains the business message.
        let messageKey: String
        /// JSON key that contains the payload object, list, or string.
        let dataKey: String
        /// Optional nested key used when a list is wrapped inside the payload object.
        let listInDataKey: String?
        /// Determines whether a decoded business code should be treated as success.
        fileprivate var codeValidator: (Int?) -> Bool

        /// Creates a configurable mapping between backend wrapper fields and decoder expectations.
        /// - Parameters:
        ///   - codeKey: JSON key that contains the business status code.
        ///   - messageKey: JSON key that contains the business message.
        ///   - dataKey: JSON key that contains the payload object, list, or string.
        ///   - listInDataKey: Optional nested key used when a list is wrapped inside the payload object.
        ///   - codeValidator: Determines whether a decoded business code should be treated as success.
        public init(codeKey: String, messageKey: String, dataKey: String, listInDataKey: String?, codeValidator: @escaping (Int?) -> Bool) {
            self.codeKey = codeKey
            self.messageKey = messageKey
            self.dataKey = dataKey
            self.listInDataKey = listInDataKey
            self.codeValidator = codeValidator
        }
    }

    /// Serial queue used to coordinate request strategy state and callback processing.
    public let queue: DispatchQueue
    /// Base URL prefix used when constructing the final URL.
    public private(set) var baseURL: String
    /// Toggles the encryption/decryption handlers for body parameters and response data.
    public private(set) var isEncryptAndDecryptEnabled: Bool = true
    /// HTTP method assigned to the outgoing request.
    public let method: Method
    /// Path appended to `baseURL`.
    public let path: String
    /// Optional request parameters supplied by the caller.
    public var params: ParamsType?
    /// Optional content type that also populates the `Content-Type` header.
    public let contentType: ContentType?
    /// Headers that will be attached to the outgoing `URLRequest`.
    public private(set) var headers: [String: String]
    /// URL loading session used to create the data task.
    public let session: URLSession
    /// Callback and transformation hooks used across the request lifecycle.
    public let handlers: Handlers
    /// Optional policy for overlapping request calls on the same `HttpRequest` instance.
    public var requestStrategy: RequestStrategy?
    /// Protects the shared request log id seed from concurrent access.
    private static let requestLogIdLock = NSLock()
    /// Monotonic seed used to correlate logs for each request task.
    private static var requestLogIdSeed = 0
    /// Tracks active or amended task state for request strategy decisions.
    private var processers = [Processer]()
    /// Subject used to debounce amended requests when a debounce interval is configured.
    private var debounceTaskSubject: PassthroughSubject<() -> Void, Never>?
    /// Retains the debounce subscription for the lifetime of the request instance.
    private var debounceTaskSubjectCancelation: AnyCancellable?
    /// Last response code observed by this request, including local, HTTP, and business codes.
    public private(set) var lastResponseCode: ResponseCode?
    /// Current response wrapper mapping and business-code validator.
    private var businessWrapperConfig: BusinessWrapperConfig

    /// Enables or disables encryption/decryption and returns `self` for fluent configuration.
    /// - Parameter enable: Whether request encryption and response decryption should be enabled.
    /// - Returns: The same request instance for fluent configuration.
    public func setEncryptAndDecryptEnabled(_ enable: Bool) -> Self {
        self.isEncryptAndDecryptEnabled = enable
        return self
    }

    /// Merges additional headers into the existing header dictionary.
    /// - Parameter headers: Header key-value pairs to add or replace.
    /// - Returns: The same request instance for fluent configuration.
    public func addHeaders(_ headers: [String: String]) -> Self {
        headers.forEach { e in
            self.headers[e.key] = e.value
        }
        return self
    }

    /// Replaces the base URL while keeping the path and other request configuration unchanged.
    /// - Parameter url: New base URL prefix used to build the final request URL.
    /// - Returns: The same request instance for fluent configuration.
    public func replaceBaseURL(_ url: String) -> Self {
        self.baseURL = url
        return self
    }

    /// Initializes a request with all transport, payload, handler, and wrapper-decoding settings.
    /// - Parameters:
    ///   - session: URL session used to create the data task.
    ///   - queue: Serial queue used for request strategy state and callback processing.
    ///   - baseURL: Base URL prefix used when constructing the final URL.
    ///   - method: HTTP method assigned to the outgoing request.
    ///   - path: Path appended to `baseURL`.
    ///   - params: Optional request parameters supplied by the caller.
    ///   - contentType: Optional content type that also populates the `Content-Type` header.
    ///   - requestStrategy: Optional policy for overlapping request calls on this instance.
    ///   - baseHeaders: Headers attached before per-request additions.
    ///   - handlers: Callback and transformation hooks used across the request lifecycle.
    ///   - businessWrapperConfig: Response wrapper mapping and business-code validator.
    public init(session: URLSession,
         queue: DispatchQueue,
         baseURL: String,
         method: Method,
         path: String,
         params: ParamsType?,
         contentType: ContentType?,
         requestStrategy: RequestStrategy?,
         baseHeaders: [String: String],
         handlers: Handlers,
                businessWrapperConfig: BusinessWrapperConfig = BusinessWrapperConfig(codeKey: "code", messageKey: "message", dataKey: "data", listInDataKey: nil) { $0 == 200 }) {
        // Store immutable transport and endpoint configuration first.
        self.queue = queue
        self.session = session
        self.baseURL = baseURL
        self.method = method
        self.path = path
        self.params = params
        self.requestStrategy = requestStrategy
        var headers = baseHeaders
        // Keep `contentType` and the actual `Content-Type` header synchronized.
        if let contentType {
            self.contentType = contentType
            headers["Content-Type"] = contentType.rawValue
        } else {
            self.contentType = nil
        }
        self.headers = headers
        self.handlers = handlers
        self.businessWrapperConfig = businessWrapperConfig
    }
}

// MARK: - Request encoding

/// Request serialization helpers.
extension HttpRequest {

    /// Encodes an `Encodable` payload as JSON and assigns it to the request body.
    private static func encodeJsonBody(_ parameters: any Encodable, into urlRequest: inout URLRequest) throws {
        do {
            let data = try JSONEncoder().encode(parameters)
            urlRequest.httpBody = data
        } catch {
            throw CodingError.encoding("json encoding failed")
        }
    }

    /// Encodes an `Encodable` payload as URL-encoded form data.
    private static func encodeFormed<Parameters: Encodable>(_ parameters: Parameters, toURL: Bool, into request: inout URLRequest) throws {

        // Form encoding needs an existing URL so query items can be merged safely.
        guard let url = request.url else {
            throw CodingError.encoding("request has no url")
        }

        // The caller must set the HTTP method before deciding where parameters belong.
        guard let _ = request.httpMethod else {
            throw CodingError.encoding("request has no method")
        }

        let encoder = URLEncodedFormEncoder()
        if toURL,
           var components = URLComponents(url: url, resolvingAgainstBaseURL: false) {
            // GET-like methods keep parameters in the URL query string.
            let query: String = try Result<String, any Error> { try encoder.encode(parameters) }
                .mapError { CodingError.encoding("encode to query error \($0)") }.get()
            // Preserve any query already present on the path and append the encoded parameters.
            let newQueryString = [components.percentEncodedQuery, query].compactMap { $0 }.joined(separator: "&")
            components.percentEncodedQuery = newQueryString.isEmpty ? nil : newQueryString

            // Rebuild the URL after updating its percent-encoded query.
            guard let newURL = components.url else {
                throw CodingError.encoding("encode error missingRequiredComponent")
            }
            request.url = newURL
        } else {
            // Non-URL parameters are sent as the request body.
            request.httpBody = try Result<Data, any Error> { try encoder.encode(parameters) }
                .mapError {  CodingError.encoding("encode to body error \($0)") }.get()
        }
    }

    /// Converts this wrapper into a concrete `URLRequest`.
    private func asURLRequest() throws -> URLRequest {
        // Combine base URL and path at the last possible moment so callers can replace either.
        guard let fullUrl = URL(string: "\(baseURL)\(path)") else {
            throw CodingError.encoding("URL error")
        }
        // Start from URLSession's native request type and then attach wrapper configuration.
        var request = URLRequest(url: fullUrl)
        request.httpMethod = method.rawValue
        request.timeoutInterval = 30
        request.allHTTPHeaderFields = headers
        var encryptedParams: (any Encodable)?
        // GET, HEAD, and DELETE requests encode parameters in the URL by convention.
        let putParamsToURL = ["get", "head", "delete"].contains(method.rawValue.lowercased())
        switch params {
        case .dic(let dic):
            // Empty dictionaries intentionally produce no body or query string.
            if dic.isEmpty {
                break
            }
            // URL query parameters are not encrypted because they must remain URL-encodable.
            if putParamsToURL || !isEncryptAndDecryptEnabled {
                encryptedParams = CodableDictionary(dic)
            } else {
                // Body dictionary parameters can be transformed by the caller-provided encryptor.
                encryptedParams = try handlers.encryptParamsHandler(dic)
            }
        case .model(let model):
            // Model parameters follow the same URL-vs-body encryption rule as dictionaries.
            if putParamsToURL || !isEncryptAndDecryptEnabled {
                encryptedParams = model
            } else {
                // Body model parameters can be transformed by the caller-provided encryptor.
                encryptedParams = try handlers.encryptModelHandler(model)
            }
        case nil:
            // Requests without parameters are still valid and keep an empty body/query.
            break
        }
        if let encryptedParams {
            // The configured content type decides the final serialization format.
            if contentType == .applicationJson {
                try Self.encodeJsonBody(encryptedParams, into: &request)
            } else {
                try Self.encodeFormed(encryptedParams, toURL: putParamsToURL, into: &request)
            }
        }
        return request
    }
}

// MARK: - Response decoding

/// Response wrapper parsing and typed result conversion.
extension HttpRequest {

    /// Captures the top-level decoder so different response shapes can be extracted later.
    private class PrepareWrapper: Decodable {

        /// Business code decoded from the configured wrapper key.
        var code: Int?
        /// Business message decoded from the configured wrapper key.
        var msg: String?
        /// Original decoder retained for deferred object, list, or string extraction.
        var decoder: Decoder? //KeyedDecodingContainer<HttpRequest.PrepareWrapper.CodingKeys>?

        /// Legacy coding keys kept for compatibility with older decoding paths.
        enum CodingKeys: String, CodingKey {
            case code, msg, data, message, result
        }

        /// Stores the decoder without consuming a specific payload shape immediately.
        public required init(from decoder: any Decoder) throws {
            self.decoder = decoder
        }

        /// Extracts wrapper metadata and returns a dynamic-key container for payload decoding.
        private func extractCodeAndMessage(by wrapperConfig: HttpRequest.BusinessWrapperConfig) throws -> KeyedDecodingContainer<JSONCodingKeys> {
            guard let decoder else {
                throw CodingError.decoding("no decoder")
            }
            let container = try decoder.container(keyedBy: JSONCodingKeys.self)
            // Accept either numeric or string business codes because backend responses vary.
            if let code = try? container.decodeIfPresent(Int.self, forKey: JSONCodingKeys(stringValue: wrapperConfig.codeKey)) {
                self.code = code
            } else if let code = try? container.decodeIfPresent(String.self, forKey: JSONCodingKeys(stringValue: wrapperConfig.codeKey)) {
                self.code = Int(code)
            } else {
                throw CodingError.decoding("no code")
            }
            msg = try container.decodeIfPresent(String.self, forKey: JSONCodingKeys(stringValue: wrapperConfig.messageKey))
            return container
        }

        /// Extracts a single object, either directly from the response body or from the wrapper payload.
        func extractObject<T: Decodable>(directly: Bool, wrapperConfig: HttpRequest.BusinessWrapperConfig) throws -> T {
            guard let decoder else {
                throw CodingError.decoding("no decoder")
            }
            if directly {
                // Direct mode lets callers decode APIs that do not use a business wrapper.
                let singleContainer = try decoder.singleValueContainer()
                let obj = try singleContainer.decode(T.self)
                return obj
            } else {
                let container = try extractCodeAndMessage(by: wrapperConfig)
                let obj: T
                if container.contains(JSONCodingKeys(stringValue: wrapperConfig.dataKey)) {
                    // Prefer the configured payload key when the wrapper contains it.
                    obj = try container.decode(T.self, forKey: JSONCodingKeys(stringValue: wrapperConfig.dataKey))
                } else {
                    // Fall back to decoding the full response for wrapper variants without a data key.
                    let singleContainer = try decoder.singleValueContainer()
                    obj = try singleContainer.decode(T.self)
                }
                return obj
            }
        }

        /// Extracts a list from the configured payload key, including an optional nested list key.
        func extractList<T: Decodable>(wrapperConfig: HttpRequest.BusinessWrapperConfig) throws -> [T] {
            let container = try extractCodeAndMessage(by: wrapperConfig)
            if container.contains(JSONCodingKeys(stringValue: wrapperConfig.dataKey)) {
                let codingKey = JSONCodingKeys(stringValue: wrapperConfig.dataKey)
                var error: Error
                do {
                    // First try the simplest wrapper shape: `{ data: [...] }`.
                    let list = try container.decode([T].self, forKey: codingKey)
                    return list
                } catch let e {
                    error = e
                }
                do {
                    // If configured, try a nested list shape such as `{ data: { list: [...] } }`.
                    guard let listInDataKey = wrapperConfig.listInDataKey else {
                        throw error
                    }
                    if let subContainer = try? container.nestedContainer(keyedBy: JSONCodingKeys.self, forKey: codingKey) {
                        let list = try subContainer.decode([T].self, forKey: JSONCodingKeys(stringValue: listInDataKey))
                        return list
                    } else {
                        throw error
                    }
                } catch let e {
                    error = e
                }
                throw error
            } else {
                throw CodingError.decoding("no key: \"\(wrapperConfig.dataKey)\" ")
            }
        }

        /// Extracts a string payload from the configured wrapper data key.
        func extractString(wrapperConfig: HttpRequest.BusinessWrapperConfig) throws -> String {
            let container = try extractCodeAndMessage(by: wrapperConfig)
            if container.contains(JSONCodingKeys(stringValue: wrapperConfig.dataKey)) {
                return try container.decode(String.self, forKey: JSONCodingKeys(stringValue: wrapperConfig.dataKey))
            } else {
                throw CodingError.decoding("no key: \"\(wrapperConfig.dataKey)\"")
            }
        }
    }

    /// Describes the response payload shape expected by a public `response` overload.
    public enum DataModelType<T: Decodable> {
        /// Decodes a single object, optionally bypassing the business wrapper.
        case obj(directly: Bool)
        /// Decodes an array of objects from the business wrapper.
        case list
        /// Decodes a string from the business wrapper.
        case string
    }

    /// Internal response decoding result before it is converted into a public `Result`.
    public enum DataResult<T> {
        /// Decoded object payload.
        case obj(T)
        /// Decoded list payload.
        case list([T])
        /// Decoded string payload.
        case string(String)
        /// Empty payload accepted by optional or empty response APIs.
        case empty
        /// Captures a decoding error while preserving any wrapper metadata already parsed.
        case decodeFailed(any Error)
    }

    /// Local error codes created by this wrapper before or after the network call.
    public enum LocalErrorCode: Int, Codable {
        /// Response payload could not be decoded into the requested model.
        case decodeFailed = -1
        /// Building the native `URLRequest` failed.
        case asURLRequestFailed = -2
        /// Request was cancelled because another task was already running.
        case cancelBecauseIsRequesting = -3
        /// Response was ignored because a newer amended request superseded it.
        case cancelBecauseBeAmended = -4
        /// URLSession returned a successful status with no response data.
        case responseDataNil = -5
        /// Decryption of response data failed.
        case dataDescryptFailed = -6
        /// Business wrapper did not contain a usable business code.
        case noBusinessCode = -7
        /// Defensive fallback for states that should not be reachable.
        case shouldNeverBe = -99
    }

    /// Unified code type for HTTP status, business status, and local wrapper errors.
    public enum ResponseCode: Codable {
        /// Non-2xx HTTP status code.
        case httpStatus(Int)
        /// Business code decoded from a 2xx response body.
        case business(Int)
        /// Local code generated by request preparation or response processing.
        case local(LocalErrorCode)

        /// Numeric representation used by callers and localized descriptions.
        public var intValue: Int {
            switch self {
            case .httpStatus(let int):
                return int
            case .business(let int):
                return int
            case .local(let localErrorCode):
                return localErrorCode.rawValue
            }
        }
    }

    /// Error object returned by public response APIs.
    public class ResponseError: Error, Codable {

        /// Categorized response code.
        public let code: ResponseCode
        /// Human-readable message from the backend or custom message handler.
        public private(set) var msg: String?
        /// Raw response body captured in debug builds for diagnosis.
        private let rawData: String?
        /// Underlying transport or decoding error that should not be encoded.
        @IgnoreValue private var subError: Error?
        /// Indicates that the error came from a decoded business code.
        public var isBusinessError: Bool {
            if case .business = code {
                return true
            }
            return false
        }
        /// Indicates that the error was generated locally by this wrapper.
        public var isLocalError: Bool {
            if case .local = code {
                return true
            }
            return false
        }

        /// Creates a response error with optional message, raw data, and underlying error.
        /// - Parameters:
        ///   - code: Categorized response code.
        ///   - msg: Human-readable message from the backend or custom message handler.
        ///   - rawData: Raw response body captured in debug builds for diagnosis.
        ///   - subError: Underlying transport or decoding error that should not be encoded.
        public init(code: ResponseCode, msg: String? = nil, rawData: String? = nil, subError: Error? = nil) {
            self.code = code
            self.msg = msg
            self.rawData = rawData
            self.subError = subError
        }

        /// Applies the optional message customization hook in-place and returns `self`.
        /// - Parameter handler: Optional closure that maps this error to a replacement message.
        /// - Returns: The same error instance after message customization.
        public func customizeMsg(_ handler: ((ResponseError) -> String)?) -> Self {
            self.msg = handler?(self) ?? msg
            return self
        }

        /// True when the failure represents request-strategy cancellation instead of backend failure.
        public var isCancelled: Bool {
            if case .local(.cancelBecauseIsRequesting) = code {
                return true
            }
            if case .local(.cancelBecauseBeAmended) = code {
                return true
            }
            return false
        }

        /// Error text exposed through Swift's `Error`/`LocalizedError` conventions.
        public var localizedDescription: String {
            return self.msg ?? "Error(\(code.intValue))"
        }
    }

    /// Decodes raw response data into the requested payload shape and preserves wrapper metadata.
    private static func extractRealData<T: Decodable>(modelType: T.Type, wrapperConfig: HttpRequest.BusinessWrapperConfig, preferType: DataModelType<T>, _ data: Data) -> (Int?, String?, DataResult<T>) {
        var wrapper: PrepareWrapper?
        do {
            let jsonDecoder = JSONDecoder()
            wrapper = try jsonDecoder.decode(PrepareWrapper.self, from: data)
            let wrapper = wrapper!
            // Route decoding through the payload shape requested by the public overload.
            switch preferType {
            case .obj(let directly):
                let obj: T = try wrapper.extractObject(directly: directly, wrapperConfig: wrapperConfig)
                return (wrapper.code, wrapper.msg, .obj(obj))
            case .list:
                let list: [T] = try wrapper.extractList(wrapperConfig: wrapperConfig)
                return (wrapper.code, wrapper.msg, .list(list))
            case .string:
                let string: String = try wrapper.extractString(wrapperConfig: wrapperConfig)
                return (wrapper.code, wrapper.msg, .string(string))
            }
        } catch let err {
            // Return any decoded business metadata even when payload decoding fails.
            return (wrapper?.code, wrapper?.msg, .decodeFailed(err))
        }

    }
}

/// Dispatches completion to the main queue when requested.
private func finalCompleted<T>(_ inMainThread: Bool, _ completed: @escaping (Result<T, HttpRequest.ResponseError>) -> Void, _ result: Result<T, HttpRequest.ResponseError>) {
    if inMainThread {
        DispatchQueue.main.async {
            completed(result)
        }
    } else {
        completed(result)
    }
}

// MARK: - Response APIs

/// Public response APIs and request execution.
extension HttpRequest {

    /// Context passed to global response error handlers.
    public struct ResponseErrorContext {
        /// Native request that produced the response error.
        public var request: URLRequest
        /// Parsed wrapper error passed to the caller.
        public var error: ResponseError
    }

    /// Emits a failure log through the configured handler.
    private func log_err(_ message: @autoclosure () -> String) {
        handlers.logSuccessHandler?(message())
    }

    /// Emits a success log through the configured handler.
    private func log_success(_ message: @autoclosure () -> String) {
        handlers.logFailureHandler?(message())
    }

    /// Generates a thread-safe id for correlating request logs.
    private static func nextRequestLogId() -> Int {
        requestLogIdLock.lock()
        defer { requestLogIdLock.unlock() }
        requestLogIdSeed &+= 1
        return requestLogIdSeed
    }

    /// Tracks one in-flight request and whether its eventual response should be ignored.
    private class Processer: Equatable {
        /// True while the URLSession task is active.
        var isRequesting: Bool = false
        /// True when a newer amended request superseded this task.
        var beenAmended: Bool = false
        /// Stable identity used for array removal and equality checks.
        var uuid = UUID().uuidString
        /// Compares task trackers by identity instead of mutable request state.
        static func == (lhs: Processer, rhs: Processer) -> Bool {
            lhs.uuid == rhs.uuid
        }
    }

    /// Replaces request parameters and returns `self` for fluent configuration.
    /// - Parameter params: New request parameters to use when the request is executed.
    /// - Returns: The same request instance for fluent configuration.
    public func replaceParams(_ params: ParamsType) -> Self {
        self.params = params
        return self
    }

    /// Replaces only the business-code validator while keeping wrapper keys unchanged.
    /// - Parameter validator: Closure that decides whether a decoded business code represents success.
    /// - Returns: The same request instance for fluent configuration.
    public func replaceBusinessCodeValidator(_ validator: @escaping (Int?) -> Bool) -> Self {
        self.businessWrapperConfig.codeValidator = validator
        return self
    }

    /// Executes the request and returns the intermediate `DataResult` used by typed overloads.
    private func response<RESPONSE_MODEL: Decodable>(responseDataType: DataModelType<RESPONSE_MODEL>, allowEmptyData: Bool = false, completed: @escaping (Result<DataResult<RESPONSE_MODEL>, ResponseError>) -> Void) {
        let request: URLRequest
        do {
            // Fail early if the wrapper cannot be converted into a native request.
            request = try self.asURLRequest()
        } catch let error {
            completed(.failure(.init(code: .local(.asURLRequestFailed).set(to: self), msg: "\(error)").customizeMsg(handlers.customizeResponseErrorMessageHandler)))
            return
        }

        let closure = {
            // Capture frequently used values so the async task has stable request context.
            let method = request.httpMethod ?? ""
            let requestLogId = Self.nextRequestLogId()
            let requestLogTitle = "[id:\(requestLogId)]HttpRequest(\(method))"
            let curProcesser = Processer()
            let params = nil != self.params ? "\(self.params!)" : ""
            let handlers = self.handlers
            let log_err = self.log_err
            let log_success = self.log_success
            if let requestStrategy = self.requestStrategy {
                if case .cancelIfRequesting = requestStrategy {
                    // Cancel the new call when this request instance already has active work.
                    for processer in self.processers {
                        if processer.isRequesting {
                            log_err("=====>🚫\n\(requestLogTitle) Request Cancelled because task is requesting\n【URL】:\n\(self.baseURL)\(self.path)\n【Method】:\(self.method)\n【Parameters】:\(params)\n【Request Headers】:\n\(self.headers)\n<=====")
                            completed(.failure(.init(code: .local(.cancelBecauseIsRequesting).set(to: self), msg: "request is requesting, cancelled").customizeMsg(handlers.customizeResponseErrorMessageHandler)))
                            return
                        }
                    }
                } else if case .amendIfRequesting = requestStrategy {
                    // Mark older tasks so their responses are abandoned when they arrive.
                    for processer in self.processers {
                        processer.beenAmended = true
                    }
                }
            }
            // Register the current task before starting URLSession work.
            self.processers.append(curProcesser)
            curProcesser.isRequesting = true
            let task = self.session.dataTask(with: request) { data, response, error in
                self.queue.async {
                    defer {
                        // Always remove the tracker once this task has reached a terminal state.
                        if let index = (self.processers.firstIndex {
                            $0.uuid == curProcesser.uuid
                        }) {
                            self.processers.remove(at: index)
                        }
                    }
                    curProcesser.isRequesting = false
                    if curProcesser.beenAmended {
                        // A newer request was sent, so this older response must not update callers.
                        log_err("=====>🚯\n\(requestLogTitle) Response Abandoned because it had been amended by new task\n【URL】:\n\(self.baseURL)\(self.path)\n【Method】:\(self.method)\n【Parameters】:\(params)\n【Request Headers】:\n\(self.headers)\n<=====")
                        completed(.failure(.init(code: .local(.cancelBecauseBeAmended).set(to: self), msg: "request is requesting, cancelled").customizeMsg(handlers.customizeResponseErrorMessageHandler)))
                        return
                    }
                    // URLSession should provide an HTTP response for HTTP requests.
                    guard let response = response as? HTTPURLResponse else {
                        completed(.failure(.init(code: .local(.shouldNeverBe).set(to: self), msg: "fatal error!!!!").customizeMsg(handlers.customizeResponseErrorMessageHandler)))
                        return
                    }
                    let statusCode = response.statusCode
                    let requestUrl = response.url?.absoluteString ?? "unknown url"
                    let headers = request.allHTTPHeaderFields ?? [:]
                    if statusCode/100 == 2 {
                        let dataDescrypt: Data
                        do {
                            // A 2xx response still needs data so decoding can continue.
                            guard let data = data else {
                                log_err("=====>❌\n\(requestLogTitle) Failed Data nil Error\n【URL】:\n\(requestUrl)\n【Parameters】:\(params)\n【Request Headers】:\n\(headers)\n<=====")
                                completed(.failure(.init(code: .local(.responseDataNil).set(to: self)).customizeMsg(handlers.customizeResponseErrorMessageHandler)))
                                return
                            }
                            // Decrypt the body only when encryption/decryption is enabled.
                            dataDescrypt = self.isEncryptAndDecryptEnabled ? try handlers.decryptDataHandler(data) : data
                        } catch let err {
                            log_err("=====>❌\n\(requestLogTitle) Failed Parse Error(\(err))\n【URL】:\n\(requestUrl)\n【Parameters】:\(params)\n【Request Headers】:\n\(headers)\n<=====")
                            completed(.failure(.init(code: .local(.dataDescryptFailed).set(to: self)).customizeMsg(handlers.customizeResponseErrorMessageHandler)))
                            return
                        }
                        let (intCode, msg, result) = Self.extractRealData(modelType: RESPONSE_MODEL.self, wrapperConfig: self.businessWrapperConfig, preferType: responseDataType, dataDescrypt)
                        #if DEBUG
                        let dataStr = String(data: dataDescrypt, encoding: .utf8) ?? ""
                        #else
                        let dataStr = ""
                        #endif
                        if self.businessWrapperConfig.codeValidator(intCode) {
                            // Business success can still have an undecodable or intentionally empty payload.
                            if case .decodeFailed(let err) = result {
                                if allowEmptyData {
                                    log_success("=====>✅\n\(requestLogTitle) Successed with Data Decode Empty(allowEmptyData == true)(\(responseDataType), \(RESPONSE_MODEL.self))\n【Empty Reason】:\n\(err)\n【URL】:\n \(requestUrl)\n【Parameters】: \(params)\n【Request Headers】:\n\(headers)\n【Raw Response Data】:\n\(dataStr)\n<=====")
                                    _ = ResponseCode.business(intCode ?? 0).set(to: self)
                                    completed(.success(.empty))
                                } else {
                                    log_err("=====>❌\n\(requestLogTitle) Failed Beacuse Data Decode Error(\(responseDataType), \(RESPONSE_MODEL.self))\n【Reason】:\(err)\n【URL】:\n\(requestUrl)\n【Parameters】: \(params)\n【Request Headers】:\n\(headers)\n【Raw Response Data】:\n\(dataStr)\n<=====")
                                    completed(.failure(.init(code: .local(.decodeFailed).set(to: self), msg: "Decode Failed").customizeMsg(handlers.customizeResponseErrorMessageHandler)))
                                }
                            } else {
                                // Store the business code and return the decoded payload.
                                log_success("=====>✅\n\(requestLogTitle) Successed\n【URL】:\n \(requestUrl)\n【Parameters】: \(params)\n【Request Headers】:\n\(headers)\n【Raw Response Data】:\n\(dataStr)\n【Decoded Model】:\n\(result)\n<=====")
                                _ = ResponseCode.business(intCode ?? 0).set(to: self)
                                completed(.success(result))
                            }
                        } else {
                            // A missing business code is treated differently from an invalid business code.
                            let code: ResponseCode = nil == intCode ? .local(.noBusinessCode) : .business(intCode!)
                            log_err("=====>❌\n\(requestLogTitle) Failed Bussiness Error: code(\(code))\n【URL】:\n \(requestUrl)\n【Message】: \n \(msg ?? "null")\n【Parameters】:\(params)\n【Request Headers】:\n\(headers)\n【Raw Response Data】:\n\(dataStr)\n<=====")
                            let error = ResponseError(code: code.set(to: self), msg: msg, rawData: dataStr).customizeMsg(handlers.customizeResponseErrorMessageHandler)
                            completed(.failure(error))
                            if let intCode, let onResponseBusinessErrorCodeHandler = handlers.onResponseBusinessErrorCodeHandler {
                                DispatchQueue.main.async {
                                    onResponseBusinessErrorCodeHandler(intCode, .init(request: request, error: error))
                                }
                            }
                        }
                    } else {
                        // Non-2xx responses bypass business decoding and surface the HTTP status.
                        log_err("=====>❌\n\(requestLogTitle) Failed Status Error(code: \(statusCode))\n【URL】:\n \(requestUrl)\n【Error】: \(error?.localizedDescription ?? "")\n【Parameters】:\(params)\n【Request Headers】:\n\(headers)\n<=====")
                        let error = ResponseError(code: .httpStatus(statusCode).set(to: self), subError: error).customizeMsg(handlers.customizeResponseErrorMessageHandler)
                        completed(.failure(error))
                        if let onResponseHttpErrorStatusCodeHandler = handlers.onResponseHttpErrorStatusCodeHandler {
                            DispatchQueue.main.async {
                                onResponseHttpErrorStatusCodeHandler(statusCode, .init(request: request, error: error))
                            }
                        }
                    }
                }
            }
            log_success("=====>\n[id:\(requestLogId)]HttpRequest Request Start\n【URL】:\n\(request.url?.absoluteString ?? "\(self.baseURL)\(self.path)")\n<=====")
            task.resume()
        }
        if case let .amendIfRequesting(debounceInterval) = requestStrategy, let debounceInterval {
            // Debounced amendment delays execution until callers stop sending new closures.
            queue.async { [self = self] in
                if nil == debounceTaskSubject {
                    debounceTaskSubject = .init()
                    debounceTaskSubjectCancelation = debounceTaskSubject?.debounce(for: .seconds(debounceInterval), scheduler: queue).sink(receiveValue: { closure in
                        closure()
                    })
                }
                debounceTaskSubject!.send(closure)
            }
        } else {
            // Default path runs the request closure on the configured serial queue.
            queue.async(execute: closure)
        }
    }

    /// Decodes a non-optional object response.
    /// - Parameters:
    ///   - objectType: Expected `Decodable` object type.
    ///   - inMainThread: Whether the completion should be delivered on the main queue.
    ///   - useBusinessWrapper: Whether to decode the object from the configured business wrapper.
    ///   - completed: Completion called with the decoded object or a `ResponseError`.
    public func response<T: Decodable>(_ objectType: T.Type, inMainThread: Bool = true, useBusinessWrapper: Bool = true, completed: @escaping (Result<T, ResponseError>) -> Void) {
        response(responseDataType: DataModelType<T>.obj(directly: !useBusinessWrapper)) { res in
            switch res {
            case .success(let success):
                // This overload expects the internal decoder to return an object payload.
                guard case let .obj(object) = success else {
                    finalCompleted(inMainThread, completed, .failure(.init(code: .local(.shouldNeverBe), msg: "should never be here!!!!").customizeMsg(self.handlers.customizeResponseErrorMessageHandler)))
                    return
                }
                finalCompleted(inMainThread, completed, .success(object))
            case .failure(let error):
                finalCompleted(inMainThread, completed, (.failure(error)))
            }
        }
    }

    /// Decodes an optional object response, treating allowed empty data as `nil`.
    /// - Parameters:
    ///   - optionObjectType: Expected optional `Decodable` object type.
    ///   - inMainThread: Whether the completion should be delivered on the main queue.
    ///   - useBusinessWrapper: Whether to decode the object from the configured business wrapper.
    ///   - completed: Completion called with the decoded optional object or a `ResponseError`.
    public func response<T: Decodable>(_ optionObjectType: (T?).Type, inMainThread: Bool = true, useBusinessWrapper: Bool = true, completed: @escaping (Result<T?, ResponseError>) -> Void) {
        response(responseDataType: DataModelType<T>.obj(directly: !useBusinessWrapper), allowEmptyData: true) { res in
            switch res {
            case .success(let success):
                // Optional object APIs map a decoded object to `.some`.
                if case let .obj(object) = success {
                    finalCompleted(inMainThread, completed, .success(object))
                    return
                }
                // Empty data is valid for optional object APIs.
                if case .empty = success {
                    finalCompleted(inMainThread, completed, .success(nil))
                    return
                }
                finalCompleted(inMainThread, completed, .failure(.init(code: .local(.shouldNeverBe), msg: "should never be here!!!!").customizeMsg(self.handlers.customizeResponseErrorMessageHandler)))
            case .failure(let error):
                finalCompleted(inMainThread, completed, (.failure(error)))
            }
        }
    }

    /// Decodes a non-optional list response.
    /// - Parameters:
    ///   - objectListType: Expected array element type wrapped as `[T].Type`.
    ///   - inMainThread: Whether the completion should be delivered on the main queue.
    ///   - completed: Completion called with the decoded list or a `ResponseError`.
    public func response<T: Decodable>(_ objectListType: [T].Type, inMainThread: Bool = true, completed: @escaping (Result<[T], ResponseError>) -> Void) {
        response(responseDataType: DataModelType<T>.list) { res in
            switch res {
            case .success(let success):
                // This overload expects the internal decoder to return a list payload.
                guard case let .list(list) = success else {
                    finalCompleted(inMainThread, completed, .failure(.init(code: .local(.shouldNeverBe), msg: "should never be here!!!!").customizeMsg(self.handlers.customizeResponseErrorMessageHandler)))
                    return
                }
                finalCompleted(inMainThread, completed, .success(list))
            case .failure(let error):
                finalCompleted(inMainThread, completed, (.failure(error)))
            }
        }
    }

    /// Decodes an optional list response, treating allowed empty data as `nil`.
    /// - Parameters:
    ///   - objectListType: Expected optional array element type wrapped as `([T]?).Type`.
    ///   - inMainThread: Whether the completion should be delivered on the main queue.
    ///   - completed: Completion called with the decoded optional list or a `ResponseError`.
    public func response<T: Decodable>(_ objectListType: ([T]?).Type, inMainThread: Bool = true, completed: @escaping (Result<[T]?, ResponseError>) -> Void) {
        response(responseDataType: DataModelType<T>.list, allowEmptyData: true) { res in
            switch res {
            case .success(let success):
                // Empty data is valid for optional list APIs.
                if case .empty = success {
                    finalCompleted(inMainThread, completed, .success(nil))
                    return
                }
                // Non-empty optional list APIs still require a decoded list payload.
                guard case let .list(list) = success else {
                    finalCompleted(inMainThread, completed, .failure(.init(code: .local(.shouldNeverBe), msg: "should never be here!!!!").customizeMsg(self.handlers.customizeResponseErrorMessageHandler)))
                    return
                }
                finalCompleted(inMainThread, completed, .success(list))
            case .failure(let error):
                finalCompleted(inMainThread, completed, (.failure(error)))
            }
        }
    }

    /// Decodes a dictionary response by routing through `CodableDictionary`.
    /// - Parameters:
    ///   - dictionaryType: Expected dictionary response marker, usually `[String: Any].self`.
    ///   - inMainThread: Whether the completion should be delivered on the main queue.
    ///   - useBusinessWrapper: Whether to decode the dictionary from the configured business wrapper.
    ///   - completed: Completion called with the decoded dictionary or a `ResponseError`.
    public func response(_ dictionaryType: [String: Any].Type, inMainThread: Bool = true, useBusinessWrapper: Bool = true, completed: @escaping (Result<[String: Any], ResponseError>) -> Void) {
        response(CodableDictionary.self, inMainThread: inMainThread, useBusinessWrapper: useBusinessWrapper) { res in
            switch res {
            case .success(let model):
                completed(.success(model.dictionary))
            case .failure(let error):
                completed(.failure(error))
            }
        }
    }

    /// Decodes an optional dictionary response by routing through optional `CodableDictionary`.
    /// - Parameters:
    ///   - dictionaryType: Expected optional dictionary response marker, usually `([String: Any]?).self`.
    ///   - inMainThread: Whether the completion should be delivered on the main queue.
    ///   - useBusinessWrapper: Whether to decode the dictionary from the configured business wrapper.
    ///   - completed: Completion called with the decoded optional dictionary or a `ResponseError`.
    public func response(_ dictionaryType: ([String: Any]?).Type, inMainThread: Bool = true, useBusinessWrapper: Bool = true, completed: @escaping (Result<[String: Any]?, ResponseError>) -> Void) {
        response((CodableDictionary?).self, inMainThread: inMainThread, useBusinessWrapper: useBusinessWrapper) { res in
            switch res {
            case .success(let model):
                completed(.success(model?.dictionary))
            case .failure(let error):
                completed(.failure(error))
            }
        }
    }

    /// Decodes an array response by routing through `CodableArray`.
    /// - Parameters:
    ///   - arrayType: Expected array response marker, usually `[Any].self`.
    ///   - inMainThread: Whether the completion should be delivered on the main queue.
    ///   - completed: Completion called with the decoded array or a `ResponseError`.
    public func response(_ arrayType: [Any].Type, inMainThread: Bool = true, completed: @escaping (Result<[Any], ResponseError>) -> Void) {
        response(CodableArray.self, inMainThread: inMainThread) { res in
            switch res {
            case .success(let model):
                completed(.success(model.array))
            case .failure(let error):
                completed(.failure(error))
            }
        }
    }

    /// Placeholder model used when only wrapper metadata or string data is required.
    private struct PlaceHolderModel: Decodable {}

    /// Decodes a string response from the configured business wrapper data key.
    /// - Parameters:
    ///   - stringType: Expected string response marker, usually `String.self`.
    ///   - inMainThread: Whether the completion should be delivered on the main queue.
    ///   - completed: Completion called with the decoded string or a `ResponseError`.
    public func response(_ stringType: String.Type, inMainThread: Bool = true, completed: @escaping (Result<String, ResponseError>) -> Void) {
        response(responseDataType: DataModelType<PlaceHolderModel>.string) { res in
            switch res {
            case .success(let success):
                // This overload expects the internal decoder to return a string payload.
                guard case let .string(str) = success else {
                    finalCompleted(inMainThread, completed, .failure(.init(code: .local(.shouldNeverBe), msg: "fatal error!!!!").customizeMsg(self.handlers.customizeResponseErrorMessageHandler)))
                    return
                }
                finalCompleted(inMainThread, completed, .success(str))
            case .failure(let error):
                finalCompleted(inMainThread, completed, .failure(error))
            }
        }
    }

    /// Executes a request where callers only care about success or failure.
    /// - Parameters:
    ///   - inMainThread: Whether the completion should be delivered on the main queue.
    ///   - useBusinessWrapper: Whether to validate success through the configured business wrapper.
    ///   - completed: Completion called with `Void` on success or a `ResponseError`.
    public func responseEmpty(inMainThread: Bool = true, useBusinessWrapper: Bool = true, completed: @escaping (Result<(), ResponseError>) -> Void) {
        response(responseDataType: DataModelType<PlaceHolderModel>.obj(directly: !useBusinessWrapper), allowEmptyData: true) { res in
            switch res {
            case .success:
                finalCompleted(inMainThread, completed, .success(()))
            case .failure(let error):
                finalCompleted(inMainThread, completed, .failure(error))
            }
        }
    }
}

// MARK: - Result helpers

/// Convenience helpers for `Result` values returned by `HttpRequest`.
extension Result where Failure == HttpRequest.ResponseError {

    /// Returns the success value or `nil` when the result is a failure.
    /// - Returns: The success value, or `nil` for a failure result.
    public func getSuccess() -> Success? {
        switch self {
        case .success(let success):
            return success
        case .failure:
            return nil
        }
    }

    /// True when the failure was caused by request-strategy cancellation.
    public var isCancelled: Bool {
        if case .failure(let error) = self {
            return error.isCancelled
        }
        return false
    }
}

/// Codable support for `Result` when the success payload can also be encoded.
extension Result where Failure == HttpRequest.ResponseError, Success: Codable {

    /// Stable top-level keys used to encode either success or failure.
    enum CodingKeys: String, CodingKey {
            case success
            case failure
        }

        /// Decodes a result by trying the success payload first and the failure payload second.
        /// - Parameter decoder: Decoder that contains either a `success` or `failure` payload.
        public init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)

            if let successValue = try? container.decode(Success.self, forKey: .success) {
                self = .success(successValue)
            } else if let failureValue = try? container.decode(Failure.self, forKey: .failure) {
                self = .failure(failureValue)
            } else {
                throw DecodingError.dataCorrupted(
                    DecodingError.Context(
                        codingPath: decoder.codingPath,
                        debugDescription: "无法解码 Result：既不是 success 也不是 failure"
                    )
                )
            }
        }

        /// Encodes exactly one branch of the result.
        /// - Parameter encoder: Encoder that receives either the `success` or `failure` payload.
        public func encode(to encoder: any Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)

            switch self {
            case .success(let value):
                try container.encode(value, forKey: .success)
            case .failure(let error):
                try container.encode(error, forKey: .failure)
            }
        }
}

/// State update helpers for response codes.
extension HttpRequest.ResponseCode {

    /// Stores this code as the request's most recent response code and returns it for chaining.
    fileprivate func set(to request: HttpRequest) -> Self {
        request.lastResponseCode = self
        return self
    }
}
