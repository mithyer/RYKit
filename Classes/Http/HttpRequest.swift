//
//  HttpRequest.swift
//  TRSTradingClient
//
//  Created by ray on 2025/3/21.
//

import Combine

// initialize
public final class HttpRequest {
            
    public enum ContentType: String {
        case applicationFormEncoded = "application/x-www-form-urlencoded"
        case applicationJson = "application/json"
    }
    
    public enum Method {
        case GET
        case POST
        case OTHER(method: String)
        
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
    
    public enum ParamsType: CustomStringConvertible {
        case dic([String: Any])
        case model(any Encodable)
        
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
    
    public enum CodingError: Error {
        case encrypt(String)
        case decrypt(String)
        case encoding(String)
        case decoding(String)
    }
    
    public enum RequestStrategy {
        case cancelIfRequesting
        case amendIfRequesting(debounceInterval: TimeInterval? = nil)
    }
    
    public struct Handlers {
        let encryptModelHandler: (_ model: any Encodable) throws -> any Encodable
        let encryptParamsHandler: (_ params: [String: Any]) throws -> any Encodable
        let decryptDataHandler: (Data) throws -> Data
        let logSuccessHandler: ((String) -> Void)?
        let logFailureHandler: ((String) -> Void)?
        let customizeResponseErrorMessageHandler: ((ResponseError) -> String)?
        let onResponseHttpErrorStatusCodeHandler: ((Int, ResponseErrorContext) -> Void)?
        let onResponseBusinessErrorCodeHandler: ((Int, ResponseErrorContext) -> Void)?
        
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
    
    public let queue: DispatchQueue
    public private(set) var baseURL: String
    public private(set) var isEncryptAndDecryptEnabled: Bool = true
    public let method: Method
    public let path: String
    public var params: ParamsType?
    public let contentType: ContentType?
    public private(set) var headers: [String: String]
    public let session: URLSession
    public let handlers: Handlers
    public var requestStrategy: RequestStrategy?
    private var processers = [Processer]()
    private var debounceTaskSubject: PassthroughSubject<() -> Void, Never>?
    private var debounceTaskSubjectCancelation: AnyCancellable?
    public private(set) var defaultHttpResponseBusinessSuccessCodes: [Int]
    private lazy var businessCodeValidator: ((Int?) -> Bool) = { value in
        self.defaultHttpResponseBusinessSuccessCodes.contains(where: {
            $0 == value
        })
    }
    public private(set) var lastResponseCode: ResponseCode?
    
    public func setHttpResponseBusinessSuccessCodes(_ codes: [Int]) -> Self {
        self.defaultHttpResponseBusinessSuccessCodes = codes
        return self
    }
    
    public func setEncryptAndDecryptEnabled(_ enable: Bool) -> Self {
        self.isEncryptAndDecryptEnabled = enable
        return self
    }
    
    public func addHeaders(_ headers: [String: String]) -> Self {
        headers.forEach { e in
            self.headers[e.key] = e.value
        }
        return self
    }
    
    public func replaceBaseURL(_ url: String) -> Self {
        self.baseURL = url
        return self
    }

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
         defaultHttpResponseBusinessSuccessCodes: [Int] = [200]) {
        self.queue = queue
        self.session = session
        self.baseURL = baseURL
        self.method = method
        self.path = path
        self.params = params
        self.requestStrategy = requestStrategy
        var headers = baseHeaders
        if let contentType {
            self.contentType = contentType
            headers["Content-Type"] = contentType.rawValue
        } else {
            self.contentType = nil
        }
        self.headers = headers
        self.handlers = handlers
        self.defaultHttpResponseBusinessSuccessCodes = defaultHttpResponseBusinessSuccessCodes
    }
}

// Request encoding
extension HttpRequest {
    
    private static func encodeJsonBody(_ parameters: any Encodable, into urlRequest: inout URLRequest) throws {
        do {
            let data = try JSONEncoder().encode(parameters)
            urlRequest.httpBody = data
        } catch {
            throw CodingError.encoding("json encoding failed")
        }
    }
    
    private static func encodeFormed<Parameters: Encodable>(_ parameters: Parameters, toURL: Bool, into request: inout URLRequest) throws {

        guard let url = request.url else {
            throw CodingError.encoding("request has no url")
        }

        guard let _ = request.httpMethod else {
            throw CodingError.encoding("request has no method")
        }
        
        let encoder = URLEncodedFormEncoder()
        if toURL,
           var components = URLComponents(url: url, resolvingAgainstBaseURL: false) {
            let query: String = try Result<String, any Error> { try encoder.encode(parameters) }
                .mapError { CodingError.encoding("encode to query error \($0)") }.get()
            let newQueryString = [components.percentEncodedQuery, query].compactMap { $0 }.joined(separator: "&")
            components.percentEncodedQuery = newQueryString.isEmpty ? nil : newQueryString

            guard let newURL = components.url else {
                throw CodingError.encoding("encode error missingRequiredComponent")
            }
            request.url = newURL
        } else {
            request.httpBody = try Result<Data, any Error> { try encoder.encode(parameters) }
                .mapError {  CodingError.encoding("encode to body error \($0)") }.get()
        }
    }
    
    private func asURLRequest() throws -> URLRequest {
        guard let fullUrl = URL(string: "\(baseURL)\(path)") else {
            throw CodingError.encoding("URL error")
        }
        var request = URLRequest(url: fullUrl)
        request.httpMethod = method.rawValue
        request.timeoutInterval = 30
        request.allHTTPHeaderFields = headers
        var encryptedParams: (any Encodable)?
        let putParamsToURL = ["get", "head", "delete"].contains(method.rawValue.lowercased())
        switch params {
        case .dic(let dic):
            if dic.isEmpty {
                break
            }
            if putParamsToURL || !isEncryptAndDecryptEnabled {
                encryptedParams = CodableDictionary(dic)
            } else {
                encryptedParams = try handlers.encryptParamsHandler(dic)
            }
        case .model(let model):
            if putParamsToURL || !isEncryptAndDecryptEnabled {
                encryptedParams = model
            } else {
                encryptedParams = try handlers.encryptModelHandler(model)
            }
        case nil:
            break
        }
        if let encryptedParams {
            if contentType == .applicationJson {
                try Self.encodeJsonBody(encryptedParams, into: &request)
            } else {
                try Self.encodeFormed(encryptedParams, toURL: putParamsToURL, into: &request)
            }
        }
        return request
    }
}

// reseponse decoding
extension HttpRequest {
    
    private class PrepareWrapper: Decodable {
        
        var code: Int?
        var msg: String?
        var decoder: Decoder? //KeyedDecodingContainer<HttpRequest.PrepareWrapper.CodingKeys>?
        
        enum CodingKeys: String, CodingKey {
            case code, msg, data, message, result
        }
        
        public required init(from decoder: any Decoder) throws {
            self.decoder = decoder
            let container = try decoder.container(keyedBy: CodingKeys.self)
            if let intCode = try? container.decode(Int.self, forKey: .code) {
                code = intCode
            } else if let strCode = try? container.decode(String.self, forKey: .code),
                      let intCode = Int(strCode) {
                code = intCode
            }
            if container.contains(.msg) {
                msg = try? container.decode(String.self, forKey: .msg)
            } else if container.contains(.message) {
                msg = try? container.decode(String.self, forKey: .message)
            }
        }
        
        func extractObject<T: Decodable>(directly: Bool) throws -> T {
            guard let decoder else {
                throw CodingError.decoding("no decoder")
            }
            if directly {
                let singleContainer = try decoder.singleValueContainer()
                let obj = try singleContainer.decode(T.self)
                return obj
            } else {
                let keyedContainer = try decoder.container(keyedBy: CodingKeys.self)
                let obj: T
                if keyedContainer.contains(.data) {
                    obj = try keyedContainer.decode(T.self, forKey: .data)
                } else if keyedContainer.contains(.result) {
                    obj = try keyedContainer.decode(T.self, forKey: .result)
                } else {
                    let singleContainer = try decoder.singleValueContainer()
                    obj = try singleContainer.decode(T.self)
                }
                return obj
            }
        }
        
        struct ListWrapper<T: Decodable>: Decodable {
            var list: [T]
            
            enum CodingKeys: CodingKey {
                case list
            }
        }
        
        func extractList<T: Decodable>() throws -> [T] {
            guard let decoder else {
                throw CodingError.decoding("no container")
            }
            var error: Error?
            let container = try decoder.container(keyedBy: CodingKeys.self)
            var codingKey: CodingKeys?
            if container.contains(.data) {
                codingKey = .data
            } else if container.contains(.result) {
                codingKey = .result
            }
            if let codingKey {
                do {
                    let list = try container.decode([T].self, forKey: codingKey)
                    return list
                } catch let e {
                    error = e
                }
                do {
                    if let subContainer = try? container.nestedContainer(keyedBy: ListWrapper<T>.CodingKeys.self, forKey: .data) {
                        let list = try subContainer.decode([T].self, forKey: .list)
                        return list
                    }
                } catch let e {
                    error = e
                }
                if let error {
                    throw error
                } else {
                    throw CodingError.decoding("should never be here")
                }
            } else {
                throw CodingError.decoding("no key: \"data\" or \"result\" ")
            }
        }
        
        func extractString() throws -> String {
            guard let decoder else {
                throw CodingError.decoding("no container")
            }
            let container = try decoder.container(keyedBy: CodingKeys.self)
            if container.contains(.data) {
                return try container.decode(String.self, forKey: .data)
            } else if container.contains(.result) {
                return try container.decode(String.self, forKey: .result)
            } else {
                throw CodingError.decoding("no key: \"data\" or \"result\" ")
            }
        }
    }
    
    public enum DataModelType<T: Decodable> {
        case obj(directly: Bool)
        case list
        case string
    }
    
    public enum DataResult<T> {
        case obj(T)
        case list([T])
        case string(String)
        case empty
        case decodeFailed(any Error)
    }
    
    public enum LocalErrorCode: Int {
        case decodeFailed = -1
        case asURLRequestFailed = -2
        case cancelBecauseIsRequesting = -3
        case cancelBecauseBeAmended = -4
        case responseDataNil = -5
        case dataDescryptFailed = -6
        case noBusinessCode = -7
        case shouldNeverBe = -99
    }
    
    public enum ResponseCode {
        case httpStatus(Int)
        case business(Int)
        case local(LocalErrorCode)
        
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
    
    public class ResponseError: Error {
        
        public let code: ResponseCode
        public private(set) var msg: String?
        private let rawData: String?
        private let subError: Error?
        public var isBusinessError: Bool {
            if case .business = code {
                return true
            }
            return false
        }
        public var isLocalError: Bool {
            if case .local = code {
                return true
            }
            return false
        }
        
        public init(code: ResponseCode, msg: String? = nil, rawData: String? = nil, subError: Error? = nil) {
            self.code = code
            self.msg = msg
            self.rawData = rawData
            self.subError = subError
        }
        
        public func customizeMsg(_ handler: ((ResponseError) -> String)?) -> Self {
            self.msg = handler?(self) ?? msg
            return self
        }
        
        public var isCancelled: Bool {
            if case .local(.cancelBecauseIsRequesting) = code {
                return true
            }
            if case .local(.cancelBecauseBeAmended) = code {
                return true
            }
            return false
        }
        
        public var localizedDescription: String {
            return self.msg ?? "Error(\(code.intValue))"
        }
    }
    
    private static func extractRealData<T: Decodable>(modelType: T.Type, preferType: DataModelType<T>, _ data: Data) -> (Int?, String?, DataResult<T>) {
        var wrapper: PrepareWrapper?
        do {
            let jsonDecoder = JSONDecoder()
            wrapper = try jsonDecoder.decode(PrepareWrapper.self, from: data)
            let wrapper = wrapper!
            switch preferType {
            case .obj(let directly):
                let obj: T = try wrapper.extractObject(directly: directly)
                return (wrapper.code, wrapper.msg, .obj(obj))
            case .list:
                let list: [T] = try wrapper.extractList()
                return (wrapper.code, wrapper.msg, .list(list))
            case .string:
                let string: String = try wrapper.extractString()
                return (wrapper.code, wrapper.msg, .string(string))
            }
        } catch let err {
            return (wrapper?.code, wrapper?.msg, .decodeFailed(err))
        }

    }
}

private func finalCompleted<T>(_ inMainThread: Bool, _ completed: @escaping (Result<T, HttpRequest.ResponseError>) -> Void, _ result: Result<T, HttpRequest.ResponseError>) {
    if inMainThread {
        DispatchQueue.main.async {
            completed(result)
        }
    } else {
        completed(result)
    }
}

// response funcs
extension HttpRequest {
    
    public struct ResponseErrorContext {
        public var request: URLRequest
        public var error: ResponseError
    }
    
    private func log_err(_ message: @autoclosure () -> String) {
        handlers.logSuccessHandler?(message())
    }
    
    private func log_success(_ message: @autoclosure () -> String) {
        handlers.logFailureHandler?(message())
    }
    
    private class Processer: Equatable {
        var isRequesting: Bool = false
        var beenAmended: Bool = false
        var uuid = UUID().uuidString
        static func == (lhs: Processer, rhs: Processer) -> Bool {
            lhs.uuid == rhs.uuid
        }
    }
    
    public func replaceParams(_ params: ParamsType) -> Self {
        self.params = params
        return self
    }
    
    public func replaceBusinessCodeValidator(_ validator: @escaping (Int?) -> Bool) -> Self {
        self.businessCodeValidator = validator
        return self
    }
    
    private func response<RESPONSE_MODEL: Decodable>(responseDataType: DataModelType<RESPONSE_MODEL>, allowEmptyData: Bool = false, completed: @escaping (Result<DataResult<RESPONSE_MODEL>, ResponseError>) -> Void) {
        let request: URLRequest
        do {
            request = try self.asURLRequest()
        } catch let error {
            completed(.failure(.init(code: .local(.asURLRequestFailed).set(to: self), msg: "\(error)").customizeMsg(handlers.customizeResponseErrorMessageHandler)))
            return
        }

        let closure = {
            let method = request.httpMethod ?? ""
            let curProcesser = Processer()
            let params = nil != self.params ? "\(self.params!)" : ""
            let handlers = self.handlers
            let log_err = self.log_err
            let log_success = self.log_success
            if let requestStrategy = self.requestStrategy {
                if case .cancelIfRequesting = requestStrategy {
                    for processer in self.processers {
                        if processer.isRequesting {
                            log_err("=====>🚫\nHttpRequest(\(method)) Request Cancelled because task is requesting\n【URL】:\n\(self.baseURL)\(self.path)\n【Method】:\(self.method)\n【Parameters】:\(params)\n【Request Headers】:\n\(self.headers)\n<=====")
                            completed(.failure(.init(code: .local(.cancelBecauseIsRequesting).set(to: self), msg: "request is requesting, cancelled").customizeMsg(handlers.customizeResponseErrorMessageHandler)))
                            return
                        }
                    }
                } else if case .amendIfRequesting = requestStrategy {
                    for processer in self.processers {
                        processer.beenAmended = true
                    }
                }
            }
            self.processers.append(curProcesser)
            curProcesser.isRequesting = true
            let task = self.session.dataTask(with: request) { data, response, error in
                self.queue.async {
                    defer {
                        if let index = (self.processers.firstIndex {
                            $0.uuid == curProcesser.uuid
                        }) {
                            self.processers.remove(at: index)
                        }
                    }
                    curProcesser.isRequesting = false
                    if curProcesser.beenAmended {
                        log_err("=====>🚯\nHttpRequest(\(method)) Response Abandoned because it had been amended by new task\n【URL】:\n\(self.baseURL)\(self.path)\n【Method】:\(self.method)\n【Parameters】:\(params)\n【Request Headers】:\n\(self.headers)\n<=====")
                        completed(.failure(.init(code: .local(.cancelBecauseBeAmended).set(to: self), msg: "request is requesting, cancelled").customizeMsg(handlers.customizeResponseErrorMessageHandler)))
                        return
                    }
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
                            guard let data = data else {
                                log_err("=====>❌\nHttpRequest(\(method)) Failed Data nil Error\n【URL】:\n\(requestUrl)\n【Parameters】:\(params)\n【Request Headers】:\n\(headers)\n<=====")
                                completed(.failure(.init(code: .local(.responseDataNil).set(to: self)).customizeMsg(handlers.customizeResponseErrorMessageHandler)))
                                return
                            }
                            dataDescrypt = self.isEncryptAndDecryptEnabled ? try handlers.decryptDataHandler(data) : data
                        } catch let err {
                            log_err("=====>❌\nHttpRequest(\(method)) Failed Parse Error(\(err))\n【URL】:\n\(requestUrl)\n【Parameters】:\(params)\n【Request Headers】:\n\(headers)\n<=====")
                            completed(.failure(.init(code: .local(.dataDescryptFailed).set(to: self)).customizeMsg(handlers.customizeResponseErrorMessageHandler)))
                            return
                        }
                        let (intCode, msg, result) = Self.extractRealData(modelType: RESPONSE_MODEL.self, preferType: responseDataType, dataDescrypt)
                        #if DEBUG
                        let dataStr = String(data: dataDescrypt, encoding: .utf8) ?? ""
                        #else
                        let dataStr = ""
                        #endif
                        if self.businessCodeValidator(intCode) {
                            if case .decodeFailed(let err) = result {
                                if allowEmptyData {
                                    log_success("=====>✅\nHttpRequest(\(method)) Successed with Data Decode Empty(allowEmptyData == true)(\(responseDataType), \(RESPONSE_MODEL.self))\n【Empty Reason】:\n\(err)\n【URL】:\n \(requestUrl)\n【Parameters】: \(params)\n【Request Headers】:\n\(headers)\n【Raw Response Data】:\n\(dataStr)\n<=====")
                                    _ = ResponseCode.business(intCode ?? 0).set(to: self)
                                    completed(.success(.empty))
                                } else {
                                    log_err("=====>❌\nHttpRequest(\(method)) Failed Beacuse Data Decode Error(\(responseDataType), \(RESPONSE_MODEL.self))\n【Reason】:\(err)\n【URL】:\n\(requestUrl)\n【Parameters】: \(params)\n【Request Headers】:\n\(headers)\n【Raw Response Data】:\n\(dataStr)\n<=====")
                                    completed(.failure(.init(code: .local(.decodeFailed).set(to: self), msg: "Decode Failed").customizeMsg(handlers.customizeResponseErrorMessageHandler)))
                                }
                            } else {
                                log_success("=====>✅\nHttpRequest(\(method)) Successed\n【URL】:\n \(requestUrl)\n【Parameters】: \(params)\n【Request Headers】:\n\(headers)\n【Raw Response Data】:\n\(dataStr)\n【Decoded Model】:\n\(result)\n<=====")
                                _ = ResponseCode.business(intCode ?? 0).set(to: self)
                                completed(.success(result))
                            }
                        } else {
                            let code: ResponseCode = nil == intCode ? .local(.noBusinessCode) : .business(intCode!)
                            log_err("=====>❌\nHttpRequest(\(method)) Failed Bussiness Error: code(\(code))\n【URL】:\n \(requestUrl)\n【Message】: \n \(msg ?? "null")\n【Parameters】:\(params)\n【Request Headers】:\n\(headers)\n【Raw Response Data】:\n\(dataStr)\n<=====")
                            let error = ResponseError(code: code.set(to: self), msg: msg, rawData: dataStr).customizeMsg(handlers.customizeResponseErrorMessageHandler)
                            completed(.failure(error))
                            if let intCode, let onResponseBusinessErrorCodeHandler = handlers.onResponseBusinessErrorCodeHandler {
                                DispatchQueue.main.async {
                                    onResponseBusinessErrorCodeHandler(intCode, .init(request: request, error: error))
                                }
                            }
                        }
                    } else {
                        log_err("=====>❌\nHttpRequest(\(method)) Failed Status Error(code: \(statusCode))\n【URL】:\n \(requestUrl)\n【Error】: \(error?.localizedDescription ?? "")\n【Parameters】:\(params)\n【Request Headers】:\n\(headers)\n<=====")
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
            task.resume()
        }
        if case let .amendIfRequesting(debounceInterval) = requestStrategy, let debounceInterval {
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
            queue.async(execute: closure)
        }
    }
    
    public func response<T: Decodable>(_ objectType: T.Type, inMainThread: Bool = true, directly: Bool = false, completed: @escaping (Result<T, ResponseError>) -> Void) {
        response(responseDataType: DataModelType<T>.obj(directly: directly)) { res in
            switch res {
            case .success(let success):
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
    
    public func response<T: Decodable>(_ optionObjectType: (T?).Type, inMainThread: Bool = true, directly: Bool = false, completed: @escaping (Result<T?, ResponseError>) -> Void) {
        response(responseDataType: DataModelType<T>.obj(directly: directly), allowEmptyData: true) { res in
            switch res {
            case .success(let success):
                if case let .obj(object) = success {
                    finalCompleted(inMainThread, completed, .success(object))
                    return
                }
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
    
    public func response<T: Decodable>(_ objectListType: [T].Type, inMainThread: Bool = true, completed: @escaping (Result<[T], ResponseError>) -> Void) {
        response(responseDataType: DataModelType<T>.list) { res in
            switch res {
            case .success(let success):
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
    
    public func response<T: Decodable>(_ objectListType: ([T]?).Type, inMainThread: Bool = true, completed: @escaping (Result<[T]?, ResponseError>) -> Void) {
        response(responseDataType: DataModelType<T>.list, allowEmptyData: true) { res in
            switch res {
            case .success(let success):
                if case .empty = success {
                    finalCompleted(inMainThread, completed, .success(nil))
                    return
                }
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
    
    public func response(_ dictionaryType: [String: Any].Type, inMainThread: Bool = true, directly: Bool = false, completed: @escaping (Result<[String: Any], ResponseError>) -> Void) {
        response(CodableDictionary.self, inMainThread: inMainThread, directly: directly) { res in
            switch res {
            case .success(let model):
                completed(.success(model.dictionary))
            case .failure(let error):
                completed(.failure(error))
            }
        }
    }
    
    public func response(_ dictionaryType: ([String: Any]?).Type, inMainThread: Bool = true, directly: Bool = false, completed: @escaping (Result<[String: Any]?, ResponseError>) -> Void) {
        response((CodableDictionary?).self, inMainThread: inMainThread, directly: directly) { res in
            switch res {
            case .success(let model):
                completed(.success(model?.dictionary))
            case .failure(let error):
                completed(.failure(error))
            }
        }
    }

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
    
    private struct PlaceHolderModel: Decodable {}
    
    public func response(_ stringType: String.Type, inMainThread: Bool = true, completed: @escaping (Result<String, ResponseError>) -> Void) {
        response(responseDataType: DataModelType<PlaceHolderModel>.string) { res in
            switch res {
            case .success(let success):
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
    
    public func responseEmpty(inMainThread: Bool = true, directly: Bool = false, completed: @escaping (Result<(), ResponseError>) -> Void) {
        response(responseDataType: DataModelType<PlaceHolderModel>.obj(directly: directly), allowEmptyData: true) { res in
            switch res {
            case .success:
                finalCompleted(inMainThread, completed, .success(()))
            case .failure(let error):
                finalCompleted(inMainThread, completed, .failure(error))
            }
        }
    }
}

extension Result where Failure == HttpRequest.ResponseError {
    
    public func getSuccess() -> Success? {
        switch self {
        case .success(let success):
            return success
        case .failure:
            return nil
        }
    }
    
    public var isCancelled: Bool {
        if case .failure(let error) = self {
            return error.isCancelled
        }
        return false
    }
}

extension HttpRequest.ResponseCode {
    
    fileprivate func set(to request: HttpRequest) -> Self {
        request.lastResponseCode = self
        return self
    }
}
