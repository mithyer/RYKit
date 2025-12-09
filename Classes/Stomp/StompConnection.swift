//
//  StompConnection.swift
//  TRSTradingClient
//
//  Created by ray on 2025/1/22.
//
// 用于管理 STOMP 的握手、连接和数据回调

import Foundation
import Combine

/// 握手请求的错误类型
fileprivate enum FetchError: Error {
    /// 网络请求错误
    case network(Error)
    /// 响应无数据
    case responseNoData
    /// 数据解码错误
    case dataDecoding(Error)
    /// 响应码不是 200
    case responseNot200(String)
    /// 握手 ID 无效
    case handshakeIdInValid
    /// 未定义的错误
    case undefined
}

/// 握手请求的状态
fileprivate enum FetchStatus<HanshakeData: HandshakeDataProtocol> {
    /// 未开始
    case unstarted
    /// 正在获取中
    case fetching
    /// 请求失败
    case error(err: FetchError)
    /// 请求成功
    case successed(data: HanshakeData)
    
    /// 获取错误信息
    var fetchError: FetchError? {
        if case .error(let err) = self {
            return err
        }
        return nil
    }
}

/// 握手数据获取器，负责从服务器获取握手 ID
fileprivate class HandShakeDataFetcher<CHANNEL: StompChannel> {
    
    /// 通道配置
    let channel: CHANNEL
    
    /// 任务执行队列
    let taskQueue: DispatchQueue
    
    /// 握手数据的过期时间
    private var expireDate: Date?
    
    /// 状态锁，用于线程安全
    private let statusLock = NSLock()
    
    /// 内部状态存储
    private var _status: FetchStatus<CHANNEL.HandshakeDataType> = .unstarted
    
    /// 当前握手请求状态（线程安全）
    private(set) var status: FetchStatus<CHANNEL.HandshakeDataType> {
        get {
            statusLock.lock()
            defer { statusLock.unlock() }
            return _status
        }
        set {
            statusLock.lock()
            _status = newValue
            statusLock.unlock()
        }
    }
    
    /// 初始化握手数据获取器
    /// - Parameters:
    ///   - channel: 通道配置
    ///   - taskQueue: 任务队列
    init(channel: CHANNEL, taskQueue: DispatchQueue) {
        self.channel = channel
        self.taskQueue = taskQueue
    }
    
    /// 开始执行握手请求任务
    func startTask() {
        
        guard case .unstarted = status else {
            return
        }
        
        self.status = .fetching
        
        let url = URL(string: channel.handshakeURL)!
        var request = URLRequest(url: url)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpMethod = "POST"
        request.httpBody = try! JSONSerialization.data(withJSONObject: channel.handshakeParams, options: [])
        request.timeoutInterval = 30
        
        let logError = { [weak self] in
            guard let self else {
                return
            }
            stomp_log("\(self.status.fetchError ?? .undefined)", .error)
        }
        
        stomp_log("fetch new handshakeID", .notice)
        let task = URLSession.shared.dataTask(with: request) { [taskQueue] data, response, error in
            taskQueue.async {
                if let error = error {
                    self.status = .error(err: .network(error))
                    return
                }
                guard let data = data else {
                    self.status = .error(err: .responseNoData)
                    logError()
                    return
                }
                let result: CHANNEL.HandshakeDataType
                do {
                    let decoder = JSONDecoder()
                    result = try decoder.decode(CHANNEL.HandshakeDataType.self, from: data)
                } catch let err {
                    self.status = .error(err: .dataDecoding(err))
                    logError()
                    return
                }
                if result.code != 200 {
                    self.status = .error(err: .responseNot200(result.msg ?? ""))
                    logError()
                    return
                }
                guard let handshakeId = result.handshakeId, !handshakeId.isEmpty else {
                    self.status = .error(err: .handshakeIdInValid)
                    logError()
                    return
                }
                if let expiresIn = result.expiresIn {
                    self.expireDate = Date().addingTimeInterval(Double(expiresIn > 20 ? expiresIn : 20))
                } else {
                    self.expireDate = Date().addingTimeInterval(20)
                }
                self.status = .successed(data: result)
            }
        }
        task.resume()
    }
    
    /// 获取握手结果或开始新的请求
    /// - Returns: 成功返回握手数据，失败返回错误，正在请求中返回 nil
    func getResultOrFetch() -> Result<CHANNEL.HandshakeDataType, FetchError>? {
        switch status {
        case .unstarted:
            startTask()
            return nil
        case .fetching:
            return nil
        case .error(let err):
            return .failure(err)
        case .successed(let data):
            if let expireDate = expireDate, expireDate > Date() {
                return .success(data)
            } else {
                self.status = .unstarted
                startTask()
                return nil
            }
        }
    }
    
}

/// STOMP 连接管理类，负责管理握手、连接和数据回调
class StompConnection<CHANNEL: StompChannel> {
    
    /// 连接错误类型
    enum ConnectionError {
        /// 握手初始化失败
        case handshakeInit
        /// URL 初始化失败
        case urlInit
        /// STOMP 初始化失败
        case stompInit
        /// 连接错误
        case connection(StompError)
        /// 未知错误
        case unknown(Float)
    }
    
    /// 连接状态
    enum Status {
        /// 未开始
        case unstarted
        /// 连接中（包含进度信息）
        case connecting(Float)
        /// 已连接
        case connected(SwiftStomp)
        /// 已断开
        case disconnected
        /// 连接失败
        case failed(ConnectionError)
    }
    
    /// 回调执行队列
    private let callbackQueue: DispatchQueue
    
    /// STOMP 连接实例
    var stomp: SwiftStomp?
    
    /// 内部状态存储
    private var _status: Status = .unstarted
    
    /// 消息监听的订阅句柄
    private var messageListenCancellable: AnyCancellable?
    
    /// 握手数据获取器
    private var handshakeIdFetcher: HandShakeDataFetcher<CHANNEL>?
    
    /// 状态锁，用于线程安全
    private let statusLock = NSLock()
    
    /// 当前连接状态（线程安全）
    private(set) var status: Status {
        get {
            statusLock.lock()
            defer {
                statusLock.unlock()
            }
            return _status
        }
        set {
            statusLock.lock()
            _status = newValue
            statusLock.unlock()
            stomp_log("connection status changed: \(status)")
        }
    }
    
    /// 通道配置
    let channel: CHANNEL
    
    /// 接收错误的回调
    var onReceiveError: ((StompError) -> Void)?
    
    /// 断开连接的回调
    var onDisconnected: (() -> Void)?
    
    /// 消息主题，用于分发接收到的消息
    var messageSubject = PassthroughSubject<StompUpstreamMessage, Never>()
    
    /// 连接成功的回调
    var onConnected: ((SwiftStomp) -> Void)?

    /// 初始化连接管理器
    /// - Parameters:
    ///   - userToken: 用户令牌
    ///   - callbackQueue: 回调执行队列
    init(userToken: String, callbackQueue: DispatchQueue) {
        self.channel = CHANNEL(userToken: userToken)
        self.callbackQueue = callbackQueue
    }
    
    /// 异步获取握手 ID
    /// - Returns: 握手数据的结果
    private func fetchHandshakeId() async -> Result<CHANNEL.HandshakeDataType, FetchError> {
        return await withCheckedTimeoutContinuation(20, timeoutReturn: {
            .failure(.undefined)
        }) { [weak self] completed in
            Task {
                if nil == self {
                    completed(.failure(.undefined))
                    return
                }
                while nil != self {
                    if let res = self?.handshakeIdFetcher?.getResultOrFetch() {
                        completed(res)
                        return
                    }
                    try await Task.sleep(nanoseconds: 1_000_000_000)
                }
                completed(.failure(.undefined))
            }
        }
    }
    
    /// 开始连接到 STOMP 服务器
    /// - Returns: 连接是否成功
    func connecting() async -> Bool {
        if case .connecting = status {
            return false
        }
        if case .connected = status {
            return true
        }
        status = .connecting(0)
        handshakeIdFetcher = .init(channel: self.channel, taskQueue: callbackQueue)
        let fetchRes = await fetchHandshakeId()
        status = .connecting(1)
        let handshakeData: CHANNEL.HandshakeDataType
        switch fetchRes {
        case let .success(data):
            handshakeData = data
            stomp_log("handshakeId fetched: \(data.handshakeId ?? "")")
            status = .connecting(2)
        case .failure(let failure):
            status = .failed(.handshakeInit)
            stomp_log("\(failure)", .error)
            return false
        }

        guard let stompURL = channel.stompURL(from: handshakeData)?.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: stompURL) else {
            status = .failed(.urlInit)
            return false
        }
        status = .connecting(3)
        if let stomp = self.stomp {
            stomp.removeListening()
            stomp.disconnect(force: true)
        }
        self.stomp = SwiftStomp(host: url, headers: channel.stompHeaders)
        let stomp = stomp!
        stomp.callbacksThread = callbackQueue
        stomp.autoReconnect = false
        stomp.enableAutoPing()

        let queue = self.callbackQueue
        let connected: Bool = await withCheckedTimeoutContinuation(30, timeoutReturn: { [weak self] in
            self?.stomp?.removeListening()
            self?.stomp = nil
            return false
        }) { [weak self, weak stomp] completed in
            stomp?.connectingCancellable = stomp?.eventsUpstream
                .receive(on: queue)
                .sink {  event in
                    guard let self, let stomp, self.stomp == stomp else {
                        self?.status = .failed(.unknown(1.1))
                        stomp?.removeListening()
                        completed(false)
                    return
                }
                switch event {
                case .connected(let type):
                    if type == .toStomp {
                        stomp_log("Stomp Connected")
                        self.status = .connected(stomp)
                        stomp.removeListening()
                        completed(true)
                        self.onConnected?(stomp)
                    } else {
                        stomp_log("WebSocket Connected")
                    }
                case .disconnected(_):
                    self.status = .disconnected
                    stomp.removeListening()
                    completed(false)
                case let .error(error):
                    if case let .fromSocket(error) = error, let nsError = error as NSError?  {
                        if nsError.domain == NSURLErrorDomain && nsError.code == NSURLErrorTimedOut {
                            stomp_log("WebSocket timeout", .error)
                        }
                    }
                    stomp_log("\(error)", .error)
                    self.status = .failed(.connection(error))
                    stomp.removeListening()
                    completed(false)
                }
            }
            stomp?.connect(timeout: 30)
        }
        if connected {
            stomp.listeningCancellable = stomp
                .eventsUpstream
                .receive(on: self.callbackQueue)
                .sink(receiveValue: { [weak self, weak stomp] event in
                    guard let self, let stomp, self.stomp == stomp else {
                        self?.status = .failed(.unknown(1.2))
                        return
                    }
                    switch event {
                    case .disconnected(let type):
                        self.stomp = nil
                        self.status = .disconnected
                        stomp_log("DISCONNECTED: \(type)")
                        self.onDisconnected?()
                    case .error(let error):
                        stomp_log("\(error)", .error)
                        self.onReceiveError?(error)
                    case .connected(let type):
                        stomp_log("CONNECTED \(type)")
                        if type == .toStomp {
                            stomp_log("Stomp Connected 2")
                            self.status = .connected(stomp)
                            self.onConnected?(stomp)
                        } else {
                            stomp_log("WebSocket Connected 2")
                        }
                    }
            })
            messageListenCancellable = stomp.messagesUpstream.subscribe(messageSubject)
        }
        return connected
    }
    
    deinit {
        messageListenCancellable?.cancel()
        self.stomp?.disconnect(force: true)
    }
}

/// SwiftStomp 的扩展，使用 Associatable 来存储订阅句柄
extension SwiftStomp {
    
    /// 连接阶段的订阅句柄（使用关联对象存储）
    fileprivate var connectingCancellable: AnyCancellable? {
        get {
            associated(#function, initializer: nil)
        }
        set {
            setAssociated(#function, value: newValue)
        }
    }
    
    /// 监听阶段的订阅句柄（使用关联对象存储）
    fileprivate var listeningCancellable: AnyCancellable? {
        get {
            associated(#function, initializer: nil)
        }
        set {
            setAssociated(#function, value: newValue)
        }
    }
    
    /// 移除所有监听订阅
    fileprivate func removeListening() {
        connectingCancellable?.cancel()
        connectingCancellable = nil
        listeningCancellable?.cancel()
        listeningCancellable = nil
    }
    
}

/// 带超时的 Continuation 包装函数
/// - Parameters:
///   - duration: 超时时间（秒）
///   - timeoutReturn: 超时时返回的值
///   - operation: 要执行的异步操作
/// - Returns: 操作结果或超时返回值
fileprivate func withCheckedTimeoutContinuation<T>(
    _ duration: TimeInterval,
    timeoutReturn: @escaping (() -> T),
    operation: @escaping (@escaping (T) -> Void) -> Void
) async -> T {
    return await withCheckedContinuation { continuation in
        let lock = NSLock()
        var isCompleted = false
        
        // timeout dealing
        let timeoutTask = DispatchWorkItem {
            lock.lock()
            if !isCompleted {
                isCompleted = true
                lock.unlock()
                continuation.resume(returning: timeoutReturn())
            } else {
                lock.unlock()
            }
        }
        
        DispatchQueue.global().asyncAfter(deadline: .now() + duration, execute: timeoutTask)
        
        // excution
        operation { result in
            lock.lock()
            if !isCompleted {
                isCompleted = true
                timeoutTask.cancel()
                lock.unlock()
                continuation.resume(returning: result)
            } else {
                lock.unlock()
            }
        }
    }
}
