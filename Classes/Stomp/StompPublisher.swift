//
//  StompPublisher.swift
//  TRSTradingClient
//
//  Created by ray on 2025/1/22.
//

import Foundation
import Combine

public protocol StompPublishCapable: AnyObject {
    associatedtype DecodableType: Decodable
    
    func setMessageCallback(identifier: String,
                            outterSubject: PassthroughSubject<StompUpstreamMessage, Never>,
                            strategy: ReceiveMessageStrategy,
                            subscribeQueue: DispatchQueue,
                            callbackQueue: DispatchQueue,
                            callback: @escaping (DecodableType, [String : String]?) -> Void) -> Bool
    func removeMessageCallback(for identifier: String)
    func removeAllCallbacks()
    var subscribed: Bool { get set }
    var destination: String { get }
    var subscribeHeaders: [String: String]? { get set }
    var hasCallbacks: Bool { get }
    var stomp: SwiftStomp? { get set }
    var decodedPublishedSubject: DecodedPublishedSubject? { get }
    var unDecodedPublishedSubject: UnDecodedPublishedSubject? { get }


    func subscribe(completed: @escaping (SubscriptionError?) -> Void)
    func unsubscribe(with headers: [String: String]?, completed: @escaping (SubscriptionError?) -> Void)
    func send(body: Data, to destination: String, receiptId: String?, headers: [String : String]?)
}

public enum SubscriptionError: Error {
    case stompNotConnected
    case stompError(StompError)
}

fileprivate class MessageDispatcher<T: Decodable> {
    
    let identifier: String
    let callback: (T, [String: String]?) -> Void
    let decoder = JSONDecoder()
    var cancelables = Set<AnyCancellable>()
    weak var callbackQueue: DispatchQueue?
    weak var publisher: (any StompPublishCapable)?

    init(identifier: String,
         publisher: any StompPublishCapable,
         outterSubject: PassthroughSubject<StompUpstreamMessage, Never>,
         strategy: ReceiveMessageStrategy,
         subscribeQueue: DispatchQueue,
         callbackQueue: DispatchQueue,
         callback: @escaping (T, [String : String]?) -> Void) {
        
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
        publisher.unDecodedPublishedSubject?.send((stringMsg, dataMsg, publisher))
        publisher.decodedPublishedSubject?.send((res, publisher))
    }
    
    func publishMessage(data: Data, headers: [String: String]?) -> T? {
        let res: T
        do {
            res = try decoder.decode(T.self, from: data)
        } catch let e {
            debugPrint("STOMP: StompPublisher.publishMessage data decoded error: \(e)")
            return nil
        }
        callbackQueue?.async {
            self.callback(res, headers)
        }
        return res
    }
    
    func publishMessage(message: String, headers: [String: String]?) -> T? {
        let res: T
        do {
            guard let data = message.data(using: .utf8) else {
                throw NSError.init(domain: "stompv2.publisher", code: -1, userInfo: [NSLocalizedDescriptionKey : "data error"])
            }
            res = try decoder.decode(T.self, from: data)
        } catch let e {
            debugPrint("STOMP: StompPublisher.publishMessage data decoded error: \(e)")
            return nil
        }
        callbackQueue?.async {
            self.callback(res, headers)
        }
        return res
    }
    
    deinit {
        // debugPrint("MessageDispatcher destination: \(publisher?.destination ?? "") \(identifier) deinit")
    }
}

// 用于同一个destination不同identifier的分发
class StompPublisher<T: Decodable>: StompPublishCapable {
    
    typealias DecodableType = T
    var stomp: SwiftStomp?
    let destination: String
    var subscribed: Bool = false
    var subscribeHeaders: [String: String]?
    weak var decodedPublishedSubject: DecodedPublishedSubject?
    weak var unDecodedPublishedSubject: UnDecodedPublishedSubject?

    fileprivate var dispatchers = [String: MessageDispatcher<T>]()
    private let subID: String
        
    var hasCallbacks: Bool {
        return !dispatchers.isEmpty
    }
    
    init(destination: String,
         decodedPublishedSubject: DecodedPublishedSubject?,
         unDecodedPublishedSubject: UnDecodedPublishedSubject?,
         type: T.Type) {
        self.destination = destination
        self.decodedPublishedSubject = decodedPublishedSubject
        self.unDecodedPublishedSubject = unDecodedPublishedSubject
        self.subID = UUID().uuidString
    }
    
    
    func setMessageCallback(identifier: String,
                            outterSubject: PassthroughSubject<StompUpstreamMessage, Never>,
                            strategy: ReceiveMessageStrategy,
                            subscribeQueue: DispatchQueue,
                            callbackQueue: DispatchQueue,
                            callback: @escaping (T, [String : String]?) -> Void) -> Bool {
        
        let preHave = dispatchers.keys.contains(identifier)
        dispatchers[identifier] = MessageDispatcher(identifier: identifier,
                                                   publisher: self,
                                                   outterSubject: outterSubject,
                                                   strategy: strategy,
                                                   subscribeQueue: subscribeQueue,
                                                   callbackQueue: callbackQueue,
                                                   callback: callback)
        return preHave
    }
    
    func removeMessageCallback(for identifier: String) {
        dispatchers.removeValue(forKey: identifier)
    }
    
    func removeAllCallbacks() {
        dispatchers.removeAll()
    }
        
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
        headers["id"] = subID
        stomp.subscribe(to: destination, headers: headers) { error in
            if let error = error {
                completed(.stompError(error))
            } else {
                self.subscribed = true
                completed(nil)
            }
        }
    }
    
    func unsubscribe(with headers: [String: String]?, completed: @escaping (SubscriptionError?) -> Void) {
        if !self.subscribed {
            completed(nil)
            return
        }
        guard let stomp = stomp, stomp.isConnected else {
            completed(.stompNotConnected)
            return
        }
        var headers = subscribeHeaders ?? [:]
        headers["id"] = subID
        stomp.unsubscribe(from: destination, headers: headers) { error in
            if let error = error {
                completed(.stompError(error))
            } else {
                self.subscribed = true
                completed(nil)
            }
        }
    }
    
    func send(body: Data, to destination: String, receiptId: String? = nil, headers: [String : String]? = nil) {
        stomp?.send(body: body, to: destination, receiptId: receiptId, headers: headers)
    }
}
