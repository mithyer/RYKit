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
    case fetching(retryTime: Int)
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
    private var curTask: URLSessionTask?

    var maxRetryTimeWhenNetworkError = 3
    var completedCall: ((Result<(new: Bool, data: CHANNEL.HandshakeDataType), FetchError>) -> Void)?
    
    init(channel: CHANNEL, taskQueue: DispatchQueue) {
        self.channel = channel
        self.taskQueue = taskQueue
    }
    
    func fetch(_ completed: @escaping (Result<(new: Bool, data: CHANNEL.HandshakeDataType), FetchError>) -> Void) {
        if case .fetching(let retryTime) = status, retryTime > 0 {
            completedCall = completed
            return
        }
        if case let .successed(data) = status {
            if let expireDate = expireDate, expireDate > Date() {
                stomp_log("use old handshakeID")
                completedCall = nil
                completed(.success((false, data)))
                return
            }
        }
        completedCall = completed
        if case .fetching = status {
            return
        }
        let url = URL(string: channel.handshakeURL)!
        var request = URLRequest(url: url)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpMethod = "POST"
        request.httpBody = try! JSONSerialization.data(withJSONObject: channel.handshakeParams, options: [])
        request.timeoutInterval = 30
        self.status = .fetching(retryTime: 0)
        
        var completeWithFailure = { [weak self] in
            guard let self else {
                return
            }
            self.completedCall?(.failure(self.status.fetchError ?? .undefined))
            stomp_log("\(self.status.fetchError ?? .undefined)", .error)
            self.completedCall = nil
        }
        stomp_log("fetch new handshakeID", .notice)
        func startTask() {
            if let task = curTask {
                curTask = nil
                task.cancel()
            }
            curTask = URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
                self?.taskQueue.async {
                    guard let self = self, self.curTask?.response == response else {
                        return
                    }
                    if let error = error {
                        if case .fetching(let retryTime) = self.status {
                            if retryTime >= self.maxRetryTimeWhenNetworkError {
                                self.status = .error(err: .network(error))
                                completeWithFailure()
                                return
                            }
                            self.status = .fetching(retryTime: retryTime + 1)
                            startTask()
                        }
                        return
                    }
                    guard let data = data else {
                        self.status = .error(err: .responseNoData)
                        completeWithFailure()
                        return
                    }
                    let result: CHANNEL.HandshakeDataType
                    do {
                        let decoder = JSONDecoder()
                        result = try decoder.decode(CHANNEL.HandshakeDataType.self, from: data)
                    } catch let err {
                        self.status = .error(err: .dataDecoding(err))
                        completeWithFailure()
                        return
                    }
                    if result.code != 200 {
                        self.status = .error(err: .responseNot200(result.msg ?? ""))
                        completeWithFailure()
                        return
                    }
                    guard let handshakeId = result.handshakeId, !handshakeId.isEmpty else {
                        self.status = .error(err: .handshakeIdInValid)
                        completeWithFailure()
                        return
                    }
                    self.expireDate = Date() + Double(((result.expiresIn ?? 20) - 20))
                    self.status = .successed(data: result)
                    self.completedCall?(.success((true, result)))
                    self.completedCall = nil
                }
            }
            curTask?.resume()
        }
        startTask()
    }
    
}

class StompConnection<CHANNEL: StompChannel> {
    
    enum ConnectionError {
        case handshakeInit
        case urlInit
        case stompInit
        case connection(StompError)
    }
    
    enum Status {
        case unstarted
        case connecting
        case connected(SwiftStomp)
        case disconnected
        case failed(ConnectionError)
    }
    
    private let callbackQueue: DispatchQueue
    var stomp: SwiftStomp?
    private var _status: Status = .unstarted
    private var eventListenCancellable: AnyCancellable?
    private var messageListenCancellable: AnyCancellable?
    private let handshakeIdFetcher: HandShakeDataFetcher<CHANNEL>
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
        }
    }
    let channel: CHANNEL
    var onReceiveError: ((StompError) -> Void)?
    var onDisconnected: (() -> Void)?
    var messageSubject = PassthroughSubject<StompUpstreamMessage, Never>()
    var onConnected: ((SwiftStomp) -> Void)?

    init(userToken: String, callbackQueue: DispatchQueue) {
        self.channel = CHANNEL(userToken: userToken)
        handshakeIdFetcher = .init(channel: self.channel, taskQueue: callbackQueue)
        self.callbackQueue = callbackQueue
    }
    
    private func fetchHandshakeId() async -> Result<(new: Bool, data: CHANNEL.HandshakeDataType), FetchError> {
        return await withCheckedContinuation { continuation in
            self.handshakeIdFetcher.fetch { result in
                continuation.resume(returning: result)
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
        status = .connecting
        let fetchRes = await fetchHandshakeId()
        let handshakeData: CHANNEL.HandshakeDataType
        switch fetchRes {
        case let .success((_, data)):
            handshakeData = data
            stomp_log("handshakeId fetched: \(data.handshakeId ?? "")")
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
        if let stomp = self.stomp {
            eventListenCancellable = nil
            stomp.disconnect(force: true)
        }
        self.stomp = SwiftStomp(host: url, headers: channel.stompHeaders)
        let stomp = stomp!
        stomp.callbacksThread = callbackQueue
        stomp.autoReconnect = false
        stomp.enableAutoPing(pingInterval: 12)

        let connected: Bool = await withCheckedContinuation { con in
            eventListenCancellable = stomp.eventsUpstream
                .receive(on: self.callbackQueue)
                .sink {  [weak self, weak stomp] event in
                guard let self = self, let stomp = stomp else {
                    return
                }
                switch event {
                case .connected(let type):
                    if type == .toStomp {
                        stomp_log("Stomp Connected")
                        self.status = .connected(stomp)
                        self.eventListenCancellable = nil
                        con.resume(returning: true)
                        self.onConnected?(stomp)
                    } else {
                        stomp_log("WebSocket Connected")
                    }
                case .disconnected(_):
                    self.status = .disconnected
                    self.eventListenCancellable = nil
                    con.resume(returning: false)
                case let .error(error):
                    if case let .fromSocket(error) = error, let nsError = error as NSError?  {
                        if nsError.domain == NSURLErrorDomain && nsError.code == NSURLErrorTimedOut {
                            stomp_log("WebSocket timeout", .error)
                        }
                    }
                    stomp_log("\(error)", .error)
                    self.status = .failed(.connection(error))
                    self.eventListenCancellable = nil
                    con.resume(returning: false)
                }
            }
            stomp.connect(timeout: 30)
        }
        if connected {
            eventListenCancellable = stomp
                .eventsUpstream
                .receive(on: self.callbackQueue)
                .sink(receiveValue: { [weak self, weak stomp] event in
                    guard let self = self, let stomp = stomp else {
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
        eventListenCancellable?.cancel()
        messageListenCancellable?.cancel()
        self.stomp?.disconnect(force: true)
    }
}
