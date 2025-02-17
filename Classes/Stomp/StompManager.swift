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

public typealias DecodedPublishedSubject = PassthroughSubject<(any Decodable, any StompPublishCapable), Never>

private let stomp_queue = DispatchQueue.init(label: "com.stompv2.event", qos: .userInteractive, autoreleaseFrequency: .workItem)

// 用于管理订阅回调的生命周期，释放后相应的回调会被移除
public class StompCallbackLifeHolder {
    
    fileprivate weak var publisher: (any StompPublishCapable)?
    fileprivate let destination: String
    fileprivate let callbackKey: String
    fileprivate weak var stomp: SwiftStomp?
    
    fileprivate init(publisher: any StompPublishCapable, callbackKey: String) {
        self.destination = publisher.destination
        self.publisher = publisher
        self.callbackKey = callbackKey
    }
    
    deinit {
        debugPrint("=====STOMPV2 NOTICE: subsciption: \(destination), \(callbackKey) will be removed because no holder exist")
        guard let publisher = publisher else {
            return
        }
        stomp_queue.async { [callbackKey = self.callbackKey] in
            publisher.removeMessageCallback(for: callbackKey)
            if !publisher.hasCallbacks {
                publisher.unsubscribe(with: nil) { _ in }
            }
        }
    }
}

// 订阅管理类，主要使用的类
public class StompManager<CHANNEL: StompChannel> {
    
    private let connection: StompConnection<CHANNEL>
    private var destinationToPublisher = [String: any StompPublishCapable]()
    private var waitToSubscribeDestinations = Set<String>()
    private var publisherLock = NSLock()
    private var checkTimer: DispatchSourceTimer?
    
    // 用于汇总最后解析完成后的数据
    public var decodedPublishedSubject = DecodedPublishedSubject()
    
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
            guard let self = self else {
                return
            }
            publisherLock.lock()
            self.destinationToPublisher.forEach { destination, publisher in
                self.waitToSubscribeDestinations.insert(destination)
            }
            publisherLock.unlock()
            debugPrint("=====STOMPV2 TRY RECONNECTION AFTER DISCONNECTED=====")
            self.startConnection(delay: 5)
            self.startRepeatCheck()
        }
        connection.onReceiveError = { error in
            debugPrint("=====STOMPV2 RECEIVED ERROR: \(error)")
        }
        connection.onConnected =  { [weak self] stomp in
            guard let self = self else {
                return
            }
            _ = checkWaitToSubscribeDestinations()
        }
    }
    
    private func checkWaitToSubscribeDestinations() -> Bool? {
        if self.waitToSubscribeDestinations.isEmpty {
            return nil
        }
        guard case .connected = self.connection.status else {
            return false
        }
        waitToSubscribeDestinations.forEach({ destination in
            let publisher = self.publisher(by: destination)
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
                        debugPrint("=====STOMPV2 NOTICE: subscribe faild, waiting retry \(destination)")
                        self?.waitToSubscribeDestinations.insert(destination)
                        self?.startRepeatCheck()
                    } else {
                        debugPrint("=====STOMPV2 NOTICE: subscribe successed \(destination)")
                    }
                }
            }
        })
        waitToSubscribeDestinations.removeAll()
        return true
    }
    
    private func startRepeatCheck() {
        if self.waitToSubscribeDestinations.isEmpty || nil != checkTimer {
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
        var secondsToWait: UInt64 = 5
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: delay * 1_000_000_000)
            guard let self = self else {
                return
            }
            while !(await self.tryConnection()) {
                debugPrint("=====STOMPV2 WILL RETRY CONNECTION AFTER \(secondsToWait) seconds=====")
                try? await Task.sleep(nanoseconds: secondsToWait * 1_000_000_000)
                secondsToWait = min(secondsToWait * 2, 60)
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
    
    private func publisher<T: Decodable>(by destination: String, dataType: T.Type) -> StompPublisher<T> {
        publisherLock.lock()
        defer {
            publisherLock.unlock()
        }
        var publisher = self.destinationToPublisher[destination]
        if nil == publisher || !(publisher is StompPublisher<T>) {
            publisher = StompPublisher(destination: destination,
                                       decodedPublishedSubject: decodedPublishedSubject,
                                       type: T.self)
            destinationToPublisher[destination] = publisher!
        }
        return publisher as! StompPublisher<T>
    }
    
    private func publisher(by destination: String) -> (any StompPublishCapable)? {
        publisherLock.lock()
        defer {
            publisherLock.unlock()
        }
        return self.destinationToPublisher[destination]
    }
    

    // dataType: model类型
    // subscription: 相同destination和identifier的订阅认为是同一个订阅
    // receiveMessageStrategy: 接收消息的策略，可以选择在间隔时间类只接收最后一条消息，并忽略掉其他消息，用于处理大量返回数据
    // dataCallback: 数据返回回调
    // return的holder: 用户生命周期管理，释放后相应的订阅会被取消
    public func subscribe<T: Decodable, S: StompSubscription>(dataType: T.Type,
                                                       subscription: S,
                                                       receiveMessageStrategy: ReceiveMessageStrategy,
                                                       callbackQueue: DispatchQueue = DispatchQueue.main,
                                                       dataCallback: @escaping (T, [String: String]?) -> Void) -> StompCallbackLifeHolder? {
        if subscription.destination.isEmpty || subscription.identifier.isEmpty {
            debugPrint("=====STOMPV2 ERROR: Cannot subscribe, destination or identifier is empty")
            return nil
        }
        startConnection()
        let publisher = self.publisher(by: subscription.destination, dataType: dataType)
        stomp_queue.async { [weak self] in
            guard let self = self else {
                return
            }
            publisher.subscribeHeaders =  subscription.subscribeHeaders
            let preExist = publisher.setMessageCallback(identifier: subscription.identifier,
                                                        outterSubject: connection.messageSubject,
                                                        strategy: receiveMessageStrategy,
                                                        subscribeQueue: stomp_queue,
                                                        callbackQueue: callbackQueue,
                                                        callback: dataCallback)
            if preExist {
                debugPrint("=====STOMPV2 WARNING: subscription exist \(subscription), will be override")
            }
            if !publisher.subscribed {
                if case .connected(let stomp) = self.connection.status {
                    publisher.stomp = stomp
                    publisher.subscribe() { [weak self] error in
                        if nil != error {
                            debugPrint("=====STOMPV2 NOTICE: subscribe faild, waiting retry \(subscription)")
                            self?.waitToSubscribeDestinations.insert(subscription.destination)
                            self?.startRepeatCheck()
                        } else {
                            debugPrint("=====STOMPV2 NOTICE: subscribe successed \(subscription)")
                        }
                    }
                } else {
                    waitToSubscribeDestinations.insert(subscription.destination)
                    startRepeatCheck()
                }
            }
        }
        return StompCallbackLifeHolder(publisher: publisher, callbackKey: subscription.callbackKey)
    }
    // 取消destination对应的某单个订阅
    public func unsbscribe<S: StompSubscription>(subscription: S) {
        stomp_queue.async { [weak self] in
            guard let self = self else {
                return
            }
            guard let publisher = publisher(by: subscription.destination) else {
                return
            }
            publisher.removeMessageCallback(for: subscription.callbackKey)
            if !publisher.hasCallbacks {
                publisher.unsubscribe(with: subscription.unsubscribeHeaders) { _ in }
            }
        }
    }
    // 取消destination对应的所有订阅
    public func unsbscribe(destination: String, with headers: [String: String]?) {
        stomp_queue.async { [weak self] in
            guard let self = self else {
                return
            }
            guard let publisher = publisher(by: destination) else {
                return
            }
            publisher.removeAllCallbacks()
            publisher.unsubscribe(with: headers) { _ in }
        }
    }

    deinit {
        checkTimer?.cancel()
        debugPrint("=====STOMPV2 NOTICE: StompManager destroyed(user token: \(userToken)")
    }
}

extension StompManager {
    
    public static var workQueue: DispatchQueue {
        return stomp_queue
    }
}

extension StompManager: Associatable {}
