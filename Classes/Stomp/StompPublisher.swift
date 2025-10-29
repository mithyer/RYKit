//
//  StompPublisher.swift
//  TRSTradingClient
//
//  Created by ray on 2025/1/22.
//

import Foundation
import Combine

/// STOMP 发布者基础协议
public protocol StompPublishBaseCapable: AnyObject {
    /// STOMP ID
    var stompID: String { get }
    /// 订阅目标地址
    var destination: String { get }
    /// 发送消息
    /// - Parameters:
    ///   - body: 消息体
    ///   - destination: 目标地址
    ///   - receiptId: 回执 ID
    ///   - headers: 请求头
    func send(body: Data, to destination: String, receiptId: String?, headers: [String : String]?)
}

/// STOMP 发布者完整协议（内部使用）
protocol StompPublishCapable: StompPublishBaseCapable {
    /// 可解码的数据类型
    associatedtype DecodableType: Decodable
    
    /// 设置消息回调
    /// - Returns: 是否已存在相同标识的回调
    func setMessageCallback(identifier: String,
                            outterSubject: PassthroughSubject<StompUpstreamMessage, Never>,
                            strategy: ReceiveMessageStrategy,
                            subscribeQueue: DispatchQueue,
                            callbackQueue: DispatchQueue,
                            callback: @escaping (DecodableType?, [String : String]?, Any) -> Void) -> Bool
    /// 移除指定标识的回调
    func removeMessageCallback(for identifier: String)
    /// 移除所有回调
    func removeAllCallbacks()
    /// 是否已订阅
    var subscribed: Bool { get set }
    /// 订阅请求头
    var subscribeHeaders: [String: String]? { get set }
    /// 是否有回调
    var hasCallbacks: Bool { get }
    /// STOMP 连接实例
    var stomp: SwiftStomp? { get set }
    /// 已解码消息主题
    var decodedPublishedSubject: DecodedPublishedSubject? { get }
    /// 未解码消息主题
    var unDecodedPublishedSubject: UnDecodedPublishedSubject? { get }

    /// 执行订阅
    func subscribe(completed: @escaping (SubscriptionError?) -> Void)
    /// 取消订阅
    func unsubscribe(completed: @escaping (SubscriptionError?) -> Void)
}

/// 订阅错误类型
enum SubscriptionError: Error {
    /// STOMP 未连接
    case stompNotConnected
    /// STOMP 错误
    case stompError(StompError)
}

/// 消息分发器，负责接收和分发特定类型的消息
fileprivate class MessageDispatcher<T: Decodable> {
    
    /// 分发器标识符
    let identifier: String
    
    /// 数据回调
    let callback: (T?, [String: String]?, Any) -> Void
    
    /// JSON 解码器
    let decoder = JSONDecoder()
    
    /// Combine 订阅句柄集合
    var cancelables = Set<AnyCancellable>()
    
    /// 回调执行队列
    weak var callbackQueue: DispatchQueue?
    
    /// 关联的发布者
    weak var publisher: (any StompPublishCapable)?

    /// 初始化消息分发器
    /// - Parameters:
    ///   - identifier: 标识符
    ///   - publisher: 发布者
    ///   - outterSubject: 外部消息主题
    ///   - strategy: 接收策略
    ///   - subscribeQueue: 订阅队列
    ///   - callbackQueue: 回调队列
    ///   - callback: 数据回调
    init(identifier: String,
         publisher: any StompPublishCapable,
         outterSubject: Publishers.Filter<PassthroughSubject<StompUpstreamMessage, Never>>,
         strategy: ReceiveMessageStrategy,
         subscribeQueue: DispatchQueue,
         callbackQueue: DispatchQueue,
         callback: @escaping (T?, [String : String]?, Any) -> Void) {
        
        self.identifier = identifier
        self.callback = callback
        self.publisher = publisher
        self.callbackQueue = callbackQueue
        
        switch strategy {
        case .all:
            outterSubject
                .subscribe(on: subscribeQueue)
                .sink(receiveValue: { [weak self] message in
                    guard let self = self else {
                        return
                    }
                    self.dealWithMessage(message)
                })
                .store(in: &cancelables)
        case .throttle(let timeInterval):
            outterSubject.first()
                .subscribe(on: subscribeQueue)
                .sink(receiveValue: { [weak self] message in
                    guard let self = self else {
                        return
                    }
                    self.dealWithMessage(message)
                })
                .store(in: &cancelables)
            outterSubject
                .dropFirst()
                .subscribe(on: subscribeQueue)
                .throttle(for: .init(floatLiteral: timeInterval), scheduler: subscribeQueue, latest: true)
                .sink(receiveValue: { [weak self] message in
                    guard let self = self else {
                        return
                    }
                    self.dealWithMessage(message)
                })
                .store(in: &cancelables)
        }
    }
    
    /// 处理接收到的消息
    /// - Parameter message: STOMP 消息
    func dealWithMessage(_ message: StompUpstreamMessage) {
        guard let publisher = self.publisher else {
            return
        }
        var stringMsg: String?
        var dataMsg: Data?
        guard let res = {
            switch message {
            case let .data(data, _, _, headers):
                dataMsg = data
                return self.publishMessage(data: data, headers: headers)
            case let .text(message, _, _, headers):
                stringMsg = message
                return self.publishMessage(message: message, headers: headers)
            }
        }() else {
            publisher.unDecodedPublishedSubject?.send((stringMsg, dataMsg, publisher))
            return
        }
        stomp_log("received msg: \(identifier): \(publisher.stompID)\ndata: \(nil != stringMsg ? stringMsg! : "")\(nil != dataMsg ? "data message" : "")", .message)
        publisher.unDecodedPublishedSubject?.send((stringMsg, dataMsg, publisher))
        publisher.decodedPublishedSubject?.send((res, publisher))
    }
    
    /// 发布二进制消息
    /// - Parameters:
    ///   - data: 消息数据
    ///   - headers: 消息头
    /// - Returns: 解码后的数据
    func publishMessage(data: Data, headers: [String: String]?) -> T? {
        var res: T?
        do {
            res = try decoder.decode(T.self, from: data)
        } catch let e {
            stomp_log("StompPublisher.publishMessage data decoded error: \(e)", .error)
        }
        callbackQueue?.async {
            self.callback(res, headers, data)
        }
        return res
    }
    
    /// 发布文本消息
    /// - Parameters:
    ///   - message: 消息字符串
    ///   - headers: 消息头
    /// - Returns: 解码后的数据
    func publishMessage(message: String, headers: [String: String]?) -> T? {
        var res: T?
        do {
            guard let data = message.data(using: .utf8) else {
                throw NSError.init(domain: "stomp.publisher", code: -1, userInfo: [NSLocalizedDescriptionKey : "data error"])
            }
            res = try decoder.decode(T.self, from: data)
        } catch let e {
            stomp_log("StompPublisher.publishMessage message decoded error: \(message) \n \(e)", .error)
        }
        callbackQueue?.async {
            self.callback(res, headers, message)
        }
        return res
    }
    
    deinit {
        // stomp_log("MessageDispatcher destination: \(publisher?.destination ?? "") \(identifier) deinit")
    }
}

/// STOMP 发布者实现类
/// 用于同一个 destination 下不同 identifier 的消息分发
class StompPublisher<T: Decodable>: StompPublishCapable {
    
    typealias DecodableType = T
    
    /// STOMP 连接实例
    weak var stomp: SwiftStomp?
    
    /// STOMP ID
    let stompID: String
    
    /// 订阅目标地址
    let destination: String
    
    /// 是否已订阅
    var subscribed: Bool = false
    
    /// 订阅请求头
    var subscribeHeaders: [String: String]?
    
    /// 已解码消息主题
    weak var decodedPublishedSubject: DecodedPublishedSubject?
    
    /// 未解码消息主题
    weak var unDecodedPublishedSubject: UnDecodedPublishedSubject?

    /// 消息分发器映射表（identifier -> MessageDispatcher）
    private var dispatchers = [String: MessageDispatcher<T>]()
    
    /// 哈希后的 STOMP ID，用于订阅头
    let hashedStompID: String

    /// 是否有回调
    var hasCallbacks: Bool {
        return !dispatchers.isEmpty
    }
    
    /// 初始化发布者
    /// - Parameters:
    ///   - destination: 目标地址
    ///   - stompID: STOMP ID
    ///   - headerIdPrefix: Header ID 前缀
    ///   - subscribeHeaders: 订阅请求头
    ///   - decodedPublishedSubject: 已解码消息主题
    ///   - unDecodedPublishedSubject: 未解码消息主题
    ///   - type: 数据类型
    init(destination: String,
         stompID: String,
         headerIdPrefix: String?,
         subscribeHeaders: [String: String]?,
         decodedPublishedSubject: DecodedPublishedSubject?,
         unDecodedPublishedSubject: UnDecodedPublishedSubject?,
         type: T.Type) {
        self.destination = destination
        self.stompID = stompID
        self.subscribeHeaders = subscribeHeaders
        self.hashedStompID = nil == headerIdPrefix ? "ios_\(stompID.sha1)" : "\(headerIdPrefix!)_ios_\(stompID.sha1)"
        self.decodedPublishedSubject = decodedPublishedSubject
        self.unDecodedPublishedSubject = unDecodedPublishedSubject
    }
    
    
    func setMessageCallback(identifier: String,
                            outterSubject: PassthroughSubject<StompUpstreamMessage, Never>,
                            strategy: ReceiveMessageStrategy,
                            subscribeQueue: DispatchQueue,
                            callbackQueue: DispatchQueue,
                            callback: @escaping (T?, [String : String]?, Any) -> Void) -> Bool {
        let preHave = dispatchers.keys.contains(identifier)
        let hashedStompID = self.hashedStompID
        let destination = self.destination
        dispatchers[identifier] = MessageDispatcher(identifier: identifier,
                                                   publisher: self,
                                                    outterSubject: outterSubject.filter({ message in
            if message.destination != destination {
                return false
            }
            guard let subID = message.subscriptionID else {
                stomp_log("Message has no subscription ID", .error)
                return false
            }
            if subID != hashedStompID {
                return false
            }
            return true
        }),
                                                   strategy: strategy,
                                                   subscribeQueue: subscribeQueue,
                                                   callbackQueue: callbackQueue,
                                                   callback: callback)
        stomp_log("local call back added: \(identifier)(\(destination)")
        return preHave
    }
    
    /// 移除指定标识的回调
    /// - Parameter identifier: 回调标识
    func removeMessageCallback(for identifier: String) {
        dispatchers.removeValue(forKey: identifier)
        stomp_log("local call back removed: \(identifier)(\(destination)")
    }
    
    /// 移除所有回调
    func removeAllCallbacks() {
#if DEBUG
        let identifiers = dispatchers.values.map {
            $0.identifier
        }
        dispatchers.removeAll()
        stomp_log("local call back removed: \(identifiers.joined(separator: ", "))(\(destination)")
#else
        dispatchers.removeAll()
#endif
    }
    
    /// 执行订阅
    /// - Parameter completed: 订阅完成回调
    func subscribe(completed: @escaping (SubscriptionError?) -> Void) {
        if self.subscribed {
            completed(nil)
            return
        }
        guard let stomp = stomp, stomp.isConnected else {
            completed(.stompNotConnected)
            return
        }
        var headers = subscribeHeaders ?? [:]
        let hashedStompID = hashedStompID
        headers["id"] = hashedStompID
        let stompID = stompID
        stomp.subscribe(to: destination, headers: headers) { error in
            if let error = error {
                stomp_log("Add sub faild(header-id: \(hashedStompID))\n\(stompID.replacingOccurrences(of: ", ", with: "\n"))\n\(error), waiting retry", .error)
                completed(.stompError(error))
            } else {
                stomp_log("Add sub successed(header-id: \(hashedStompID))\n\(stompID.replacingOccurrences(of: ", ", with: "\n"))")
                self.subscribed = true
                completed(nil)
            }
        }
    }
    
    /// 取消订阅
    /// - Parameter completed: 取消订阅完成回调
    func unsubscribe(completed: @escaping (SubscriptionError?) -> Void) {
        if !self.subscribed {
            completed(nil)
            return
        }
        guard let stomp = stomp, stomp.isConnected else {
            completed(.stompNotConnected)
            return
        }
        let stompID = stompID
        let destination = destination
        self.subscribed = false
        let hashedStompID = hashedStompID
        stomp.unsubscribe(from: destination, headers: ["id": hashedStompID]) { error in
            if let error = error {
                stomp_log("Remove sub faild(header-id: \(hashedStompID))\n\(stompID.replacingOccurrences(of: ", ", with: "\n"))\n\(error)", .error)
                completed(.stompError(error))
            } else {
                stomp_log("Remove sub successed(header-id: \(hashedStompID))\n\(stompID.replacingOccurrences(of: ", ", with: "\n"))")
                completed(nil)
            }
        }
    }
    
    /// 发送消息到指定目标
    /// - Parameters:
    ///   - body: 消息体
    ///   - destination: 目标地址
    ///   - receiptId: 回执 ID
    ///   - headers: 请求头
    func send(body: Data, to destination: String, receiptId: String? = nil, headers: [String : String]? = nil) {
        stomp?.send(body: body, to: destination, receiptId: receiptId, headers: headers)
    }
}
