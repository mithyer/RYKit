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

public class GlobalReachability {
    
    public static let shared = GlobalReachability()
    
    private let reachability = try? Reachability()
    
    private class Listener {
        
        weak var observer: AnyObject?
        var callback: (Reachability.Connection) -> Void
        
        init(callback: @escaping (Reachability.Connection) -> Void) {
            listeningCount += 1
            self.callback = callback
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
            _ = removeObserver()
        }
    }
    
    public func listen(_ onChanged: @escaping (Reachability.Connection) -> Void) -> AnyObject? {
        guard let reachability = reachability else {
            return nil
        }
        let listener = Listener(callback: onChanged)
        listener.observer = NotificationCenter.default.addObserver(forName: .reachabilityChanged, object: reachability, queue: .main, using: { [unowned listener] noti in
            guard let reachability = noti.object as? Reachability else {
                return
            }
            listener.callback(reachability.connection)
        })
        try? reachability.startNotifier()
        return listener
    }

    public func unlisten(_ listener: AnyObject) {
        guard let listener = listener as? Listener else {
            return
        }
        if listener.removeObserver() {
            if listeningCount <= 0 {
                reachability?.stopNotifier()
            }
        }
    }
}
