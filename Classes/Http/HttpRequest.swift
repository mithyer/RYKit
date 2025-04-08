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
        case applicationFormEncoded = "application/x-www-form-urlencoded; charset=utf-8"
        case applicationJson = "application/json"
    }
    
    public enum Method: String {
        case GET
        case POST
    }
    
    public enum ParamsType {
        case dic([String: Any])
        case model(any Encodable)
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
        let onResponseHttpErrorStatusCodeHandler: ((Int) -> Void)?
        let onResponseBusinessErrorCodeHandler: ((Int) -> Void)?
        
        public init(encryptModelHandler: @escaping (_: any Encodable) throws -> any Encodable,
                    encryptParamsHandler: @escaping (_: [String : Any]) throws -> any Encodable,
                    decryptDataHandler: @escaping (Data) throws -> Data,
                    logSuccessHandler: ((String) -> Void)?,
                    logFailureHandler: ((String) -> Void)?,
                    customizeResponseErrorMessageHandler: ((ResponseError) -> String)?,
                    onResponseHttpErrorStatusCodeHandler: ((Int) -> Void)?,
                    onResponseBusinessErrorCodeHandler: ((Int) -> Void)?) {
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
    public let baseURL: String
    public let method: Method
    public let path: String
    public var params: ParamsType?
    public let contentType: ContentType?
    public let headers: [String: String]
    public let session: URLSession
    public let handlers: Handlers
    public var requestStrategy: RequestStrategy?
    private var processers = [Processer]()
    private var debounceTaskSubject: PassthroughSubject<() -> Void, Never>?
    private var debounceTaskSubjectCancelation: AnyCancellable?

    public init(session: URLSession,
         queue: DispatchQueue,
         baseURL: String,
         method: Method,
         path: String,
         params: ParamsType?,
         contentType: ContentType?,
         requestStrategy: RequestStrategy?,
         baseHeaders: [String: String],
         handlers: Handlers) {
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
    }
}

// Request encoding
extension HttpRequest {
    
    private static func encodeJsonBody(_ parameters: Any, into urlRequest: inout URLRequest) throws {

        guard JSONSerialization.isValidJSONObject(parameters) else {
            throw CodingError.encoding("parameters isn't valid json")
        }
        do {
            let data = try JSONSerialization.data(withJSONObject: parameters, options: [])
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
        guard let fullUrl = URL(string: "\(baseURL)\(path.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? path)") else {
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
            if putParamsToURL {
                encryptedParams = CodableDictionary(dic)
            } else {
                encryptedParams = try handlers.encryptParamsHandler(dic)
            }
        case .model(let model):
            if putParamsToURL {
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
        
        var code: Int
        var msg: String?
        var container: KeyedDecodingContainer<HttpRequest.PrepareWrapper.CodingKeys>?
        
        enum CodingKeys: String, CodingKey {
            case code, msg, data, message
        }
        
        public required init(from decoder: any Decoder) throws {
            container = try decoder.container(keyedBy: CodingKeys.self)
            if let intCode = try? container!.decode(Int.self, forKey: .code) {
                code = intCode
            } else if let strCode = try? container!.decode(String.self, forKey: .code),
                      let intCode = Int(strCode) {
                code = intCode
            } else {
                throw CodingError.decoding("No code can be extracted!!!!")
            }
            msg = (try? container!.decode(String.self, forKey: .msg)) ?? (try? container!.decode(String.self, forKey: .message))
        }
        
        func extractObject<T: Decodable>() throws -> T {
            guard let container else {
                throw CodingError.decoding("no container")
            }
            let obj = try container.decode(T.self, forKey: .data)
            self.container = nil
            return obj
        }
        
        struct ListWrapper<T: Decodable>: Decodable {
            var list: [T]
        }
        
        func extractList<T: Decodable>() throws -> [T] {
            guard let container else {
                throw CodingError.decoding("no container")
            }
            var error: (any Error)?
            do {
                let list = try container.decode([T].self, forKey: .data)
                self.container = nil
                return list
            } catch let e {
                error = e
            }
            do {
                let data = try container.decode(ListWrapper<T>.self, forKey: .data)
                self.container = nil
                return data.list
            } catch let e {
                error = e
            }
            if let error {
                throw error
            } else {
                throw CodingError.decoding("should never be here")
            }
        }
        
        func extractString() throws -> String {
            guard let container else {
                throw CodingError.decoding("no container")
            }
            let str = try container.decode(String.self, forKey: .data)
            self.container = nil
            return str
        }
    }
    
    public enum DataModelType<T: Decodable> {
        case obj
        case list
        case string
        case empty
    }
    
    public enum DataResult<T: Decodable> {
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
    
    public class ResponseError: Error {
        public enum CodeType {
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
        public let code: CodeType
        public private(set) var msg: String?
        private let rawData: String?
        private let subError: Error?
        
        public init(code: CodeType, msg: String? = nil, rawData: String? = nil, subError: Error? = nil) {
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
    }
    
    private static func extractRealData<T: Decodable>(modelType: T.Type, preferType: DataModelType<T>, _ data: Data) -> (Int?, String?, DataResult<T>) {
        var wrapper: PrepareWrapper?
        do {
            let jsonDecoder = JSONDecoder()
            wrapper = try jsonDecoder.decode(PrepareWrapper.self, from: data)
            let wrapper = wrapper!
            switch preferType {
            case .obj:
                let obj: T = try wrapper.extractObject()
                return (wrapper.code, wrapper.msg, .obj(obj))
            case .list:
                let list: [T] = try wrapper.extractList()
                return (wrapper.code, wrapper.msg, .list(list))
            case .string:
                let string: String = try wrapper.extractString()
                return (wrapper.code, wrapper.msg, .string(string))
            case .empty:
                return (wrapper.code, wrapper.msg, .empty)
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
    
    private func log_err(_ message: @autoclosure () -> String) {
        handlers.logSuccessHandler?(message())
    }
    
    private func log_success(_ message: @autoclosure () -> String) {
        handlers.logFailureHandler?(message())
    }
    
    static var httpResponseBusinessSuccessCode: Int = 200
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
    
    private func response<RESPONSE_MODEL: Decodable>(responseDataType: DataModelType<RESPONSE_MODEL>, allowEmptyData: Bool = false, completed: @escaping (Result<DataResult<RESPONSE_MODEL>, ResponseError>) -> Void) {
        let request: URLRequest
        do {
            request = try self.asURLRequest()
        } catch let error {
            completed(.failure(.init(code: .local(.asURLRequestFailed), msg: "\(error)").customizeMsg(handlers.customizeResponseErrorMessageHandler)))
            return
        }

        let closure = {
            let curProcesser = Processer()
            let params = nil != self.params ? "\(self.params!)" : ""
            let handlers = self.handlers
            let log_err = self.log_err
            let log_success = self.log_success
            if let requestStrategy = self.requestStrategy {
                if case .cancelIfRequesting = requestStrategy {
                    for processer in self.processers {
                        if processer.isRequesting {
                            log_err("=====>🚫\nHTTP Request Cancelled because task is requesting\nURL:\(self.baseURL)\(self.path)\nMethod:\(self.method)\nParameters：\(params)\nRequest Headers：\(self.headers)\n<=====")
                            completed(.failure(.init(code: .local(.cancelBecauseIsRequesting), msg: "request is requesting, cancelled").customizeMsg(handlers.customizeResponseErrorMessageHandler)))
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
                        log_err("=====>🚯\nHTTP Response Abandoned because it had been amended by new task\nURL:\(self.baseURL)\(self.path)\nMethod:\(self.method)\nParameters：\(params)\nRequest Headers：\(self.headers)\n<=====")
                        completed(.failure(.init(code: .local(.cancelBecauseBeAmended), msg: "request is requesting, cancelled").customizeMsg(handlers.customizeResponseErrorMessageHandler)))
                        return
                    }
                    guard let response = response as? HTTPURLResponse else {
                        completed(.failure(.init(code: .local(.shouldNeverBe), msg: "fatal error!!!!").customizeMsg(handlers.customizeResponseErrorMessageHandler)))
                        return
                    }
                    let statusCode = response.statusCode
                    let requestUrl = response.url?.absoluteString ?? "unknown url"
                    let headers = request.allHTTPHeaderFields ?? [:]
                    if statusCode/100 == 2 {
                        if responseDataType == .empty {
                            completed(.success(.empty))
                            return
                        }
                        let dataDescrypt: Data
                        do {
                            guard let data = data else {
                                log_err(" =====>❌\nHTTP Failed Data nil Error\nURL:\(requestUrl)\nParameters：\(params)\nRequest Headers：\(headers)\n<=====")
                                completed(.failure(.init(code: .local(.responseDataNil)).customizeMsg(handlers.customizeResponseErrorMessageHandler)))
                                return
                            }
                            dataDescrypt = try handlers.decryptDataHandler(data)
                        } catch let err {
                            log_err(" =====>❌\nHTTP Failed Parse Error(\(err))\nURL:\(requestUrl)\nParameters：\(params)\nRequest Headers：\(headers)\n<=====")
                            completed(.failure(.init(code: .local(.dataDescryptFailed)).customizeMsg(handlers.customizeResponseErrorMessageHandler)))
                            return
                        }
                        let (intCode, msg, result) = Self.extractRealData(modelType: RESPONSE_MODEL.self, preferType: responseDataType, dataDescrypt)
                        #if DEBUG
                        let dataStr = String(data: dataDescrypt, encoding: .utf8) ?? ""
                        #else
                        let dataStr = ""
                        #endif
                        if intCode != Self.httpResponseBusinessSuccessCode {
                            let code: ResponseError.CodeType = nil == intCode ? .local(.noBusinessCode) : .business(intCode!)
                            log_err("=====>❌\nHTTP Failed Bussiness Error: code(\(code))\nURL: \(requestUrl)\nMessage: \(msg ?? "null")\nParameters：\(params)\nRequest Headers：\(headers)\nRaw Response Data: \(dataStr)\n<=====")
                            completed(.failure(.init(code: code, msg: msg, rawData: dataStr).customizeMsg(handlers.customizeResponseErrorMessageHandler)))
                            if let intCode, let onResponseBusinessErrorCodeHandler = handlers.onResponseBusinessErrorCodeHandler {
                                DispatchQueue.main.async {
                                    onResponseBusinessErrorCodeHandler(intCode)
                                }
                            }
                        } else {
                            if case .decodeFailed(let err) = result {
                                if allowEmptyData {
                                    log_success("=====>✅\nHTTP Successed with Data Decode Empty(Option Model)(\(responseDataType), \(RESPONSE_MODEL.self))\nReason:\(err)\nURL: \(requestUrl)\nParameters：\(params)\nRequest Headers：\(headers)\nRaw Response Data: \(dataStr)\n<=====")
                                    completed(.success(.empty))
                                } else {
                                    log_err("=====>❌\nHTTP Failed Beacuse Data Decode Error(\(responseDataType), \(RESPONSE_MODEL.self))\nReason:\(err)\nURL: \(requestUrl)\nParameters: \(params)\nRequest Headers：\(headers)\nRaw Response Data: \(dataStr)\n<=====")
                                    completed(.failure(.init(code: .local(.decodeFailed), msg: "Decode Failed").customizeMsg(handlers.customizeResponseErrorMessageHandler)))
                                }
                            } else {
                                log_success("=====>✅\nHTTP Successed\nURL: \(requestUrl)\nParameters: \(params)\nRequest Headers：\(headers)\nRaw Response Data: \(dataStr)\nDecoded Model:\(result)\n<=====")
                                completed(.success(result))
                            }
                        }
                    } else {
                        log_err("=====>❌\nHTTP Failed Status Error(code: \(statusCode))\nURL: \(requestUrl)\nError: \(error?.localizedDescription ?? "")\nParameters：\(params)\nRequest Headers：\(headers)\n<=====")
                        completed(.failure(.init(code: .httpStatus(statusCode), subError: error).customizeMsg(handlers.customizeResponseErrorMessageHandler)))
                        if let onResponseHttpErrorStatusCodeHandler = handlers.onResponseHttpErrorStatusCodeHandler {
                            DispatchQueue.main.async {
                                onResponseHttpErrorStatusCodeHandler(statusCode)
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
    
    public func response<T: Decodable>(_ objectType: T.Type, inMainThread: Bool = true, completed: @escaping (Result<T, ResponseError>) -> Void) {
        response(responseDataType: DataModelType<T>.obj) { res in
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
    
    public func response<T: Decodable>(_ optionObjectType: (T?).Type, inMainThread: Bool = true, completed: @escaping (Result<T?, ResponseError>) -> Void) {
        response(responseDataType: DataModelType<T>.obj, allowEmptyData: true) { res in
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
    
    public func response(_ dictionaryType: [String: Any].Type, inMainThread: Bool = true, completed: @escaping (Result<[String: Any], ResponseError>) -> Void) {
        response(CodableDictionary.self, inMainThread: inMainThread) { res in
            switch res {
            case .success(let model):
                completed(.success(model.dictionary))
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
    
    public func responseEmpty(inMainThread: Bool = true, completed: @escaping (Result<(), ResponseError>) -> Void) {
        response(responseDataType: DataModelType<PlaceHolderModel>.empty) { res in
            switch res {
            case .success(let success):
                guard case .empty = success else {
                    finalCompleted(inMainThread, completed, .failure(.init(code: .local(.shouldNeverBe), msg: "fatal error!!!!").customizeMsg(self.handlers.customizeResponseErrorMessageHandler)))
                    return
                }
                finalCompleted(inMainThread, completed, .success(()))
            case .failure(let error):
                finalCompleted(inMainThread, completed, .failure(error))
            }
        }
    }
}

extension Result where Failure == HttpRequest.ResponseError {
    
    public func getExist() -> Success? {
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
