//
//  GlobalReachability.swift
//  TRSTradingClient
//
//  Created by ray on 2025/2/17.
//
import Foundation
import Combine

private var lock = NSLock()
private var _listeningCount = 0
private var listeningCount: Int {
    set(value) {
        lock.lock()
        _listeningCount = value
        lock.unlock()
    }
    get {
        defer {
            lock.unlock()
        }
        lock.lock()
        return _listeningCount
    }
}

private var reachability: SwiftReachability?

public class GlobalReachability {
    
    public enum Connection: String {
        case unavailable, wifi, cellular, unknown
        init(connection: SwiftReachability.Connection) {
            if let connection = Connection.init(rawValue: connection.rawValue) {
                self = connection
            } else {
                self = .unknown
            }
        }
    }
    
    public static let shared = GlobalReachability()
    
    private class Listener {
        
        weak var observer: AnyObject?
        
        var reachabilitySubjectCancelation: AnyCancellable?
        
        init(connection: SwiftReachability.Connection, callback: @escaping (Connection) -> Void) {
            listeningCount += 1
            let subject = PassthroughSubject<Connection, Never>()
            observer = NotificationCenter.default.addObserver(forName: .reachabilityChanged, object: nil, queue: .main, using: { noti in
                guard let reachability = noti.object as? SwiftReachability else {
                    return
                }
                subject.send(.init(connection: reachability.connection))
            })
            reachabilitySubjectCancelation = subject
                .receive(on: DispatchQueue.main)
                .sink { connection in
                    callback(connection)
            }
        }
        
        private func removeObserver() -> Bool {
            guard let observer else {
                return false
            }
            listeningCount -= 1
            NotificationCenter.default.removeObserver(observer)
            return true
        }
        
        deinit {
            guard removeObserver() else {
                return
            }
            if listeningCount <= 0 {
                DispatchQueue.main.async {
                    reachability?.stopNotifier()
                }
            }
        }
    }
    
    private init() {}
    
    public func listen(_ onChanged: @escaping (Connection) -> Void) -> AnyObject? {
        if nil == reachability {
            reachability = try? SwiftReachability()
        }
        guard let reachability else {
            return nil
        }
        let listener = Listener(connection: reachability.connection, callback: onChanged)
        DispatchQueue.main.async {
            try? reachability.startNotifier()
        }
        return listener
    }
}
