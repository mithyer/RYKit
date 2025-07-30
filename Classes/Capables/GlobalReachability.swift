//
//  GlobalReachability.swift
//  TRSTradingClient
//
//  Created by ray on 2025/2/17.
//

import Combine

fileprivate var lock = NSLock()
fileprivate var _listeningCount = 0
fileprivate var listeningCount: Int {
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
    
    public static let shared = GlobalReachability()
    
    private class Listener {
        
        weak var observer: AnyObject?
        
        var reachabilitySubjectCancelation: AnyCancellable?
        
        init(connection: SwiftReachability.Connection, callback: @escaping (SwiftReachability.Connection) -> Void) {
            listeningCount += 1
            let subject = PassthroughSubject<SwiftReachability.Connection, Never>()
            observer = NotificationCenter.default.addObserver(forName: .reachabilityChanged, object: nil, queue: .main, using: { noti in
                guard let reachability = noti.object as? SwiftReachability else {
                    return
                }
                subject.send(reachability.connection)
            })
            reachabilitySubjectCancelation = subject
                .dropFirst()
                .receive(on: DispatchQueue.main)
                .sink { connection in
                callback(connection)
            }
        }
        
        func removeObserver() -> Bool {
            guard let observer = observer else {
                return false
            }
            self.observer = nil
            listeningCount -= 1
            NotificationCenter.default.removeObserver(observer)
            return true
        }
        
        deinit {
            guard removeObserver() else {
                return
            }
            if listeningCount <= 0 {
                reachability?.stopNotifier()
            }
        }
    }
    
    public func listen(_ onChanged: @escaping (SwiftReachability.Connection) -> Void) -> AnyObject? {
        if nil == reachability {
            reachability = try? SwiftReachability()
        }
        guard let reachability = reachability else {
            return nil
        }
        let listener = Listener(connection: reachability.connection, callback: onChanged)
        DispatchQueue.main.async {
            try? reachability.startNotifier()
        }
        return listener
    }
}
