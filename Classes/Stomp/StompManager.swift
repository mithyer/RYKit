//
//  StompManager.swift
//  TRSTradingClient
//
//  Created by ray on 2025/1/22.
//

import Foundation
import Combine

/// 接收消息的策略
public enum ReceiveMessageStrategy {
    /// 不过滤任何消息，接收所有消息
    case all
    /// 节流模式，在指定时间间隔内只接收最后一条消息
    /// throttle 原理参考: https://juejin.cn/post/7097406389466693640
    case throttle(TimeInterval)
}

/// 已解码消息的主题类型
public typealias DecodedPublishedSubject = PassthroughSubject<(decoded: any Decodable, publisher: any StompPublishBaseCapable), Never>

/// 未解码消息的主题类型
public typealias UnDecodedPublishedSubject = PassthroughSubject<(stringMessage: String?, dataMessage: Data?, publisher: any StompPublishBaseCapable), Never>

/// STOMP 内部工作队列
private let stomp_queue = DispatchQueue.init(label: "com.stomp.event", qos: .userInteractive, autoreleaseFrequency: .workItem)

/// 订阅回调生命周期管理器
/// 用于管理订阅回调的生命周期，当对象释放时自动移除相应的回调
public class StompCallbackLifeHolder {
    
    /// 订阅发布者
    fileprivate weak var publisher: (any StompPublishCapable)?
    
    /// 订阅目标地址
    fileprivate let destination: String
    
    /// 回调的唯一标识
    fileprivate let callbackKey: String
    
    /// STOMP 连接实例
    fileprivate weak var stomp: SwiftStomp?
    
    /// 析构时的回调
    fileprivate var onDeinit: (() -> Void)?
    
    /// 初始化生命周期管理器
    /// - Parameters:
    ///   - publisher: 发布者
    ///   - callbackKey: 回调标识
    ///   - onDeinit: 析构回调
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

/// STOMP 订阅管理器（主要使用的类）
/// 负责管理订阅、连接和消息分发
open class StompManager<CHANNEL: StompChannel> {
    
    /// STOMP 连接管理器
    private let connection: StompConnection<CHANNEL>
    
    /// STOMP ID 到发布者的映射表
    private var stompIDToPublisher = [String: any StompPublishCapable]()
    
    /// 等待订阅的 STOMP ID 集合（用于重连后恢复订阅）
    private var waitToSubscribeStompIDs = Set<String>()
    
    /// 发布者锁，用于线程安全
    private var publisherLock = NSLock()
    
    /// 定时检查器，用于重试失败的订阅
    private var checkTimer: DispatchSourceTimer?
    
    /// 等待重连的时间间隔（秒）
    private var secondsToWaitReConnection: UInt64 = 5

    /// 已解码消息的主题，用于汇总所有解析完成的数据
    public var decodedPublishedSubject = DecodedPublishedSubject()
    
    /// 未解码消息的主题
    public var unDecodedPublishedSubject = UnDecodedPublishedSubject()
    
    /// 是否启用日志（已废弃，请使用 StompLog）
    public var enableLog: Bool = false
    
    /// 连接状态主题
    public var connectedSubject = CurrentValueSubject<Bool, Never>(false)

    /// 是否已连接
    public var connected: Bool {
        if case .connected = connection.status {
            return true
        }
        return false
    }
    
    /// 当前用户令牌
    public var userToken: String {
        return connection.channel.userToken
    }
    
    /// 初始化订阅管理器
    /// 不同的用户令牌对应不同的 manager 实例
    /// - Parameter userToken: 用户令牌
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
            publisherLock.lock()
            stompIDToPublisher.values.forEach { publisher in
                publisher.stomp = stomp
            }
            publisherLock.unlock()
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
    
    private var connectionThread: Thread?
    
    /// 启动连接
    /// 可以提前调用，也可以在订阅时自动懒加载
    /// - Parameter delay: 延迟启动的时间（秒），默认为 0
    public func startConnection(delay: UInt64 = 0) {
        switch connection.status {
        case .unstarted, .disconnected:
            break
        default:
            return
        }
        var waitSeconds = secondsToWaitReConnection
        if nil == connectionThread || connectionThread!.isCancelled || connectionThread!.isFinished {
            if !Thread.isMainThread {
                Thread.sleep(forTimeInterval: TimeInterval(delay))
            }
            connectionThread = Thread.init(block: { [weak self] in
                while let self = self {
                    if case .connected = connection.status {
                        Thread.exit()
                        connectionThread = nil
                        return
                    }
                    publisherLock.lock()
                    if stompIDToPublisher.isEmpty {
                        publisherLock.unlock()
                        Thread.sleep(forTimeInterval: TimeInterval(secondsToWaitReConnection))
                        continue
                    }
                    publisherLock.unlock()
                    Task {
                        await self.tryConnection()
                    }
                    stomp_log("StompManager(\(userToken)) WILL RETRY IF LOST CONNECTION AFTER \(waitSeconds) seconds")
                    Thread.sleep(forTimeInterval: TimeInterval(waitSeconds))
                    waitSeconds = min(waitSeconds + 1, 15)
                }
            })
            connectionThread?.start()
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
    
    private func publisher<T: Decodable>(by destination: String, stompID: String, headerIdPrefix: String?, subscribeHeaders: [String: String]?, dataType: T.Type) -> StompPublisher<T> {
        publisherLock.lock()
        defer {
            publisherLock.unlock()
        }
        var publisher = self.stompIDToPublisher[stompID]
        if nil == publisher || !(publisher is StompPublisher<T>) {
            publisher = StompPublisher(destination: destination,
                                        stompID: stompID,
                                        headerIdPrefix: headerIdPrefix,
                                        subscribeHeaders: subscribeHeaders,
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
    
    /// 订阅结果
    public enum SubscribeResult {
        /// 订阅成功
        case success(headerId: String)
        /// 订阅失败
        case failed(headerId: String, error: any Error)
    }

    /// 订阅指定的 destination
    /// - Parameters:
    ///   - dataType: 消息数据的模型类型
    ///   - subscription: 订阅信息，相同 destination 和 identifier 被认为是同一个订阅
    ///   - receiveMessageStrategy: 接收消息的策略，可选择节流模式来忽略高频消息
    ///   - callbackQueue: 回调执行的队列，默认为主队列
    ///   - subscribedCallback: 订阅完成的回调
    ///   - headerIdPrefix: Header ID 的前缀
    ///   - dataCallback: 数据接收回调
    /// - Returns: 生命周期管理器，释放后自动取消订阅
    public func subscribe<T: Decodable>(dataType: T.Type,
                                        subscription: StompSubInfo,
                                        receiveMessageStrategy: ReceiveMessageStrategy,
                                        callbackQueue: DispatchQueue = DispatchQueue.main,
                                        subscribedCallback: ((SubscribeResult) -> Void)? = nil,
                                        headerIdPrefix: String? = nil,
                                        dataCallback: @escaping (T?, [String: String]?, Any) -> Void) -> StompCallbackLifeHolder? {
        if subscription.destination.isEmpty || subscription.identifier.isEmpty {
            stomp_log("StompManager(\(userToken) Cannot subscribe, destination or identifier is empty", .error)
            return nil
        }
        let stompID = subscription.stompID(token: userToken)
        let publisher = self.publisher(by: subscription.destination,
                                       stompID: stompID,
                                       headerIdPrefix: headerIdPrefix,
                                       subscribeHeaders: subscription.headers,
                                       dataType: dataType)
        startConnection()
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
                    publisher.subscribe() { [weak self, weak publisher] error in
                        if let error = error {
                            self?.waitToSubscribeStompIDs.insert(subscription.destination)
                            self?.startRepeatCheck()
                            subscribedCallback?(.failed(headerId: publisher?.hashedStompID ?? "", error: error))
                        } else {
                            subscribedCallback?(.success(headerId: publisher?.hashedStompID ?? ""))
                        }
                    }
                } else {
                    waitToSubscribeStompIDs.insert(stompID)
                    startRepeatCheck()
                }
            } else {
                subscribedCallback?(.success(headerId: publisher.hashedStompID))
                stomp_log("StompManager(\(userToken) publiser already subscribed \(stompID)")
            }
        }
        return StompCallbackLifeHolder(publisher: publisher, callbackKey: subscription.identifier) { [weak self] in
            guard let self else {
                return
            }
            if let publisher = self.publisher(by: stompID), !publisher.hasCallbacks {
                publisherLock.lock()
                self.stompIDToPublisher.removeValue(forKey: stompID)
                publisherLock.unlock()
            }
        }
    }
    /// 取消指定的订阅
    /// - Parameter subscription: 要取消的订阅信息
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

/// StompManager 扩展
extension StompManager {
    
    /// STOMP 内部工作队列
    public static var workQueue: DispatchQueue {
        return stomp_queue
    }
}

/// 使 StompManager 支持关联对象存储
extension StompManager: Associatable {}
