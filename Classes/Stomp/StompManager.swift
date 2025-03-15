//
//  StompManager.swift
//  TRSTradingClient
//
//  Created by ray on 2025/1/22.
//

import Foundation
import Combine

public enum ReceiveMessageStrategy {
    // 不过滤掉任何一条消息
    case all
    // throttle原理(Combine相同) https://juejin.cn/post/7097406389466693640
    case throttle(TimeInterval)
}

public typealias DecodedPublishedSubject = PassthroughSubject<(decoded: any Decodable, publisher: any StompPublishBaseCapable), Never>
public typealias UnDecodedPublishedSubject = PassthroughSubject<(stringMessage: String?, dataMessage: Data?, publisher: any StompPublishBaseCapable), Never>

private let stomp_queue = DispatchQueue.init(label: "com.stomp.event", qos: .userInteractive, autoreleaseFrequency: .workItem)

// 用于管理订阅回调的生命周期，释放后相应的回调会被移除
public class StompCallbackLifeHolder {
    
    fileprivate weak var publisher: (any StompPublishCapable)?
    fileprivate let destination: String
    fileprivate let callbackKey: String
    fileprivate weak var stomp: SwiftStomp?
    fileprivate var onDeinit: (() -> Void)?
    
    fileprivate init(publisher: any StompPublishCapable, callbackKey: String, onDeinit: @escaping () -> Void) {
        self.destination = publisher.destination
        self.publisher = publisher
        self.callbackKey = callbackKey
        self.onDeinit = onDeinit
    }
    
    deinit {
        guard let publisher = publisher else {
            return
        }
        let onDeinit = self.onDeinit
        stomp_queue.async { [callbackKey = self.callbackKey] in
            publisher.removeMessageCallback(for: callbackKey)
            if !publisher.hasCallbacks {
                publisher.unsubscribe() { _ in }
            }
            onDeinit?()
        }
    }
}

// 订阅管理类，主要使用的类
open class StompManager<CHANNEL: StompChannel> {
    
    private let connection: StompConnection<CHANNEL>
    private var stompIDToPublisher = [String: any StompPublishCapable]()
    private var waitToSubscribeStompIDs = Set<String>()
    private var publisherLock = NSLock()
    private var checkTimer: DispatchSourceTimer?
    private var secondsToWaitReConnection: UInt64 = 5

    // 用于汇总最后解析完成后的数据
    public var decodedPublishedSubject = DecodedPublishedSubject()
    public var unDecodedPublishedSubject = UnDecodedPublishedSubject()
    public var enableLog: Bool = false
    public var connectedSubject = CurrentValueSubject<Bool, Never>(false)

    public var connected: Bool {
        if case .connected = connection.status {
            return true
        }
        return false
    }
    
    public var userToken: String {
        return connection.channel.userToken
    }
    
    // 不同的user对应不同的manager
    public init(userToken: String) {
        connection = .init(userToken: userToken, callbackQueue: stomp_queue)
        connection.onDisconnected = { [weak self] in
            self?.connectedSubject.send(false)
            guard let self = self else {
                return
            }
            switch self.connection.status {
            case .connecting:
                return
            default:
                break
            }
            publisherLock.lock()
            self.stompIDToPublisher.forEach { stompID, publisher in
                if publisher.subscribed {
                    self.waitToSubscribeStompIDs.insert(stompID)
                }
            }
            publisherLock.unlock()
            stomp_log("StompManager(\(userToken)) TRY RECONNECTION AFTER DISCONNECTED")
            self.startConnection(delay: 1)
            self.startRepeatCheck()
        }
        connection.onReceiveError = { error in
            stomp_log("StompManager(\(userToken)) RECEIVED ERROR: \(error)", .error)
        }
        connection.onConnected =  { [weak self] stomp in
            self?.connectedSubject.send(true)
            guard let self = self else {
                return
            }
            stompIDToPublisher.values.forEach { publisher in
                publisher.stomp = stomp
            }
            secondsToWaitReConnection = 5
            _ = checkWaitToSubscribeDestinations()
        }
        stomp_log("StompManager(\(userToken)) initialized")
    }
    
    private func checkWaitToSubscribeDestinations() -> Bool? {
        if self.waitToSubscribeStompIDs.isEmpty {
            return nil
        }
        guard case .connected = self.connection.status else {
            return false
        }
        waitToSubscribeStompIDs.forEach({ stompID in
            let publisher = self.publisher(by: stompID)
            guard let publisher = publisher, let stomp = self.connection.stomp else {
                return
            }
            publisher.stomp = stomp
            publisher.subscribed = false
            if !publisher.hasCallbacks {
                return
            }
            publisher.subscribe() { [weak self] error in
                stomp_queue.async {
                    if nil != error {
                        self?.waitToSubscribeStompIDs.insert(stompID)
                        self?.startRepeatCheck()
                    }
                }
            }
        })
        waitToSubscribeStompIDs.removeAll()
        return true
    }
    
    private func startRepeatCheck() {
        if self.waitToSubscribeStompIDs.isEmpty || nil != checkTimer {
            return
        }
        let timer = DispatchSource.makeTimerSource(flags: [], queue: stomp_queue)
        timer.schedule(deadline: .now() + 5, repeating: 10)
        timer.setEventHandler { [weak self] in
            guard let self = self else {
                return
            }
            if nil == self.checkWaitToSubscribeDestinations() {
                self.checkTimer?.cancel()
                self.checkTimer = nil
            }
        }
        timer.resume()
        checkTimer = timer
    }

    
    // 可提前调用，也可订阅时自动懒加载
    public func startConnection(delay: UInt64 = 0) {
        switch connection.status {
        case .unstarted, .disconnected:
            break
        default:
            return
        }
        StompManager.workQueue.async {
            Task { [weak self] in
                try? await Task.sleep(nanoseconds: delay * 1_000_000_000)
                while let self = self, !(await self.tryConnection()) {
                    stomp_log("StompManager(\(userToken) WILL RETRY CONNECTION AFTER \(secondsToWaitReConnection) seconds")
                    try? await Task.sleep(nanoseconds: secondsToWaitReConnection * 1_000_000_000)
                    secondsToWaitReConnection = min(secondsToWaitReConnection + 1, 30)
                }
            }
        }
    }
    
    private func tryConnection() async -> Bool {
        switch connection.status {
        case .connected, .connecting:
            return true
        default:
            if await connection.connecting() {
                return true
            }
            return false
        }
    }
    
    private func publisher<T: Decodable>(by destination: String, stompID: String, dataType: T.Type) -> StompPublisher<T> {
        publisherLock.lock()
        defer {
            publisherLock.unlock()
        }
        var publisher = self.stompIDToPublisher[stompID]
        if nil == publisher || !(publisher is StompPublisher<T>) {
            publisher = StompPublisher(destination: destination,
                                        stompID: stompID,
                                        decodedPublishedSubject: decodedPublishedSubject,
                                        unDecodedPublishedSubject: unDecodedPublishedSubject,
                                        type: T.self)
            stompIDToPublisher[stompID] = publisher!
        }
        return publisher as! StompPublisher<T>
    }
    
    private func publisher(by stompID: String) -> (any StompPublishCapable)? {
        publisherLock.lock()
        defer {
            publisherLock.unlock()
        }
        return self.stompIDToPublisher[stompID]
    }
    

    // dataType: model类型
    // subscription: 相同destination和identifier的订阅认为是同一个订阅
    // receiveMessageStrategy: 接收消息的策略，可以选择在间隔时间类只接收最后一条消息，并忽略掉其他消息，用于处理大量返回数据
    // dataCallback: 数据返回回调
    // return的holder: 用户生命周期管理，释放后相应的订阅会被取消
    public func subscribe<T: Decodable>(dataType: T.Type,
                                        subscription: StompSubInfo,
                                        receiveMessageStrategy: ReceiveMessageStrategy,
                                        callbackQueue: DispatchQueue = DispatchQueue.main,
                                        subscribedCallback: ((Result<(), Error>) -> Void)? = nil,
                                        dataCallback: @escaping (T?, [String: String]?, Any) -> Void) -> StompCallbackLifeHolder? {
        if subscription.destination.isEmpty || subscription.identifier.isEmpty {
            stomp_log("StompManager(\(userToken) Cannot subscribe, destination or identifier is empty", .error)
            return nil
        }
        startConnection()
        let stompID = subscription.stompID(token: userToken)
        let publisher = self.publisher(by: subscription.destination, stompID: stompID, dataType: dataType)
        publisher.subscribeHeaders =  subscription.headers
        stomp_queue.async { [weak self] in
            guard let self = self else {
                return
            }
            let preExist = publisher.setMessageCallback(identifier: subscription.identifier,
                                                        outterSubject: connection.messageSubject,
                                                        strategy: receiveMessageStrategy,
                                                        subscribeQueue: stomp_queue,
                                                        callbackQueue: callbackQueue,
                                                        callback: dataCallback)
            if preExist {
                stomp_log("StompManager(\(userToken) subscription exist \(subscription.identifier), will be override", .warning)
            }
            if !publisher.subscribed {
                if case .connected(let stomp) = self.connection.status {
                    publisher.stomp = stomp
                    publisher.subscribe() { [weak self] error in
                        if let error = error {
                            self?.waitToSubscribeStompIDs.insert(subscription.destination)
                            self?.startRepeatCheck()
                            subscribedCallback?(.failure(error))
                        } else {
                            subscribedCallback?(.success(()))
                        }
                    }
                } else {
                    waitToSubscribeStompIDs.insert(stompID)
                    startRepeatCheck()
                }
            } else {
                stomp_log("StompManager(\(userToken) publiser already subscribed \(stompID)")
            }
        }
        return StompCallbackLifeHolder(publisher: publisher, callbackKey: subscription.identifier) { [weak self] in
            guard let self else {
                return
            }
            publisherLock.lock()
            stompIDToPublisher.removeValue(forKey: stompID)
            publisherLock.unlock()
        }
    }
    // 取消destination对应的某单个订阅
    public func unsbscribe(subscription: StompSubInfo) {
        stomp_queue.async { [weak self] in
            guard let self = self else {
                return
            }
            guard let publisher = publisher(by: subscription.stompID(token: userToken)) else {
                return
            }
            publisher.removeMessageCallback(for: subscription.identifier)
            if !publisher.hasCallbacks {
                publisher.unsubscribe() { _ in }
            }
        }
    }

    deinit {
        checkTimer?.cancel()
        stomp_log("StompManager(\(userToken)) destroyed")
    }
}

extension StompManager {
    
    public static var workQueue: DispatchQueue {
        return stomp_queue
    }
}

extension StompManager: Associatable {}
