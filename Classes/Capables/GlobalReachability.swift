//
//  GlobalReachability.swift
//  TRSTradingClient
//
//  Created by ray on 2025/2/17.
//

import Reachability

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

private var reachability: Reachability?

public class GlobalReachability {
    
    public static let shared = GlobalReachability()
    
    private class Listener {
        
        weak var observer: AnyObject?
        
        init(callback: @escaping (Reachability.Connection) -> Void) {
            listeningCount += 1
            observer = NotificationCenter.default.addObserver(forName: .reachabilityChanged, object: reachability, queue: .main, using: { noti in
                guard let reachability = noti.object as? Reachability else {
                    return
                }
                callback(reachability.connection)
            })
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
    
    public func listen(_ onChanged: @escaping (Reachability.Connection) -> Void) -> AnyObject? {
        if nil == reachability {
            reachability = try? Reachability()
        }
        guard let reachability = reachability else {
            return nil
        }
        let listener = Listener(callback: onChanged)
        DispatchQueue.main.async {
            try? reachability.startNotifier()
        }
        return listener
    }
}
