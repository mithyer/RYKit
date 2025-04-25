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

    var maxRetryTimeWhenNetworkError = 3
    
    init(channel: CHANNEL, taskQueue: DispatchQueue) {
        self.channel = channel
        self.taskQueue = taskQueue
    }
    
    func startTask() {
        
        guard case .unstarted = status else {
            return
        }
        
        self.status = .fetching(retryTime: 0)
        
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
                    if case .fetching(let retryTime) = self.status {
                        if retryTime >= self.maxRetryTimeWhenNetworkError {
                            self.status = .error(err: .network(error))
                            logError()
                        } else {
                            self.status = .fetching(retryTime: retryTime + 1)
                            self.startTask()
                        }
                    } else {
                        self.status = .error(err: .network(error))
                    }
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
    
    private func fetchHandshakeId() async -> Result<CHANNEL.HandshakeDataType, FetchError> {
        return await withCheckedContinuation { continuation in
            Task {
                while true {
                    if let res = self.handshakeIdFetcher.getResultOrFetch() {
                        continuation.resume(with: .success(res))
                        return
                    }
                    try await Task.sleep(nanoseconds: 1_000_000_000)
                }
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
        case let .success(data):
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
                    con.resume(returning: false)
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
