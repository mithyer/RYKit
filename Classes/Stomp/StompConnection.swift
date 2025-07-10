//
//  StompConnection.swift
//  TRSTradingClient
//
//  Created by ray on 2025/1/22.
//
// 用于管理stomp的握手、连接和数据回调

import Foundation
import Combine

fileprivate enum FetchError: Error {
    case network(Error)
    case responseNoData
    case dataDecoding(Error)
    case responseNot200(String)
    case handshakeIdInValid
    case undefined
}

fileprivate enum FetchStatus<HanshakeData: HandshakeDataProtocol> {
    case unstarted
    case fetching
    case error(err: FetchError)
    case successed(data: HanshakeData)
    
    var fetchError: FetchError? {
        if case .error(let err) = self {
            return err
        }
        return nil
    }
}

fileprivate class HandShakeDataFetcher<CHANNEL: StompChannel> {
    
    let channel: CHANNEL
    let taskQueue: DispatchQueue
    private var expireDate: Date?
    private let statusLock = NSLock()
    private var _status: FetchStatus<CHANNEL.HandshakeDataType> = .unstarted
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
    
    init(channel: CHANNEL, taskQueue: DispatchQueue) {
        self.channel = channel
        self.taskQueue = taskQueue
    }
    
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

class StompConnection<CHANNEL: StompChannel> {
    
    enum ConnectionError {
        case handshakeInit
        case urlInit
        case stompInit
        case connection(StompError)
        case unknown(Float)
    }
    
    enum Status {
        case unstarted
        case connecting(Float)
        case connected(SwiftStomp)
        case disconnected
        case failed(ConnectionError)
    }
    
    private let callbackQueue: DispatchQueue
    var stomp: SwiftStomp?
    private var _status: Status = .unstarted
    private var messageListenCancellable: AnyCancellable?
    private var handshakeIdFetcher: HandShakeDataFetcher<CHANNEL>?
    private let statusLock = NSLock()
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
    let channel: CHANNEL
    var onReceiveError: ((StompError) -> Void)?
    var onDisconnected: (() -> Void)?
    var messageSubject = PassthroughSubject<StompUpstreamMessage, Never>()
    var onConnected: ((SwiftStomp) -> Void)?

    init(userToken: String, callbackQueue: DispatchQueue) {
        self.channel = CHANNEL(userToken: userToken)
        self.callbackQueue = callbackQueue
    }
    
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

extension SwiftStomp: Associatable {
    
    fileprivate var connectingCancellable: AnyCancellable? {
        get {
            associated(#function, initializer: nil)
        }
        set {
            setAssociated(#function, value: newValue)
        }
    }
    
    fileprivate var listeningCancellable: AnyCancellable? {
        get {
            associated(#function, initializer: nil)
        }
        set {
            setAssociated(#function, value: newValue)
        }
    }
    
    fileprivate func removeListening() {
        connectingCancellable?.cancel()
        connectingCancellable = nil
        listeningCancellable?.cancel()
        listeningCancellable = nil
    }
    
}

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
