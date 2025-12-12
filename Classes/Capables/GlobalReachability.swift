//
//  GlobalReachability.swift
//  TRSTradingClient
//
//  Created by ray on 2025/2/17.
//

import Network
import Foundation
import Combine

private let queue = DispatchQueue(label: "com.rykit.GlobalReachability")

public class GlobalReachability {
    
    // MARK: - 网络状态枚举
    public enum NetworkStatus: Equatable {
        
        public enum ConnectionType {
            case wifi
            case cellular
            case wiredEthernet // 有线以太网
            case other
        }
        
        case connected(ConnectionType)
        case disconnected
        case unknown
    }
    
    public static let shared = GlobalReachability()
    
    private class Listener: Associatable {
        
        let monitor = NetworkMonitor()
        
        init(callback: @escaping (NetworkStatus) -> Void) {
            monitor.$currentStatus.receive(on: queue).removeDuplicates(by: { l, r in
                l == r
            }).sink { status in
                callback(status)
            }.ry.store(to: self)
        }
    }
    
    private init() {}
    
    public func listen(_ onChanged: @escaping (NetworkStatus) -> Void) -> AnyObject? {
        Listener(callback: onChanged)
    }
}

fileprivate extension NWPath {
    
    var connectionAndStatus: (GlobalReachability.NetworkStatus.ConnectionType, GlobalReachability.NetworkStatus) {
        let path = self
        let connectionType: GlobalReachability.NetworkStatus.ConnectionType
        let currentStatus: GlobalReachability.NetworkStatus
        // 判断连接类型
        if path.usesInterfaceType(.wifi) {
            connectionType = .wifi
        } else if path.usesInterfaceType(.cellular) {
            connectionType = .cellular
        } else if path.usesInterfaceType(.wiredEthernet) {
            connectionType = .wiredEthernet
        } else {
            connectionType = .other
        }
        // 更新状态
        let isConnected = path.status == .satisfied && path.availableInterfaces.count > 0
        if isConnected {
            currentStatus = .connected(connectionType)
        } else {
            currentStatus = .disconnected
        }
        return (connectionType, currentStatus)
    }
}

// MARK: - 网络监听管理器
fileprivate class NetworkMonitor {
    
    private let monitor = NWPathMonitor()
    
    @CurrentValue private(set) var connectionType: GlobalReachability.NetworkStatus.ConnectionType
    @CurrentValue private(set) var currentStatus: GlobalReachability.NetworkStatus
    
    // 状态变化回调
    init() {
        let connectionAndStatus = monitor.currentPath.connectionAndStatus
        connectionType = connectionAndStatus.0
        currentStatus = connectionAndStatus.1
        monitor.pathUpdateHandler = { [weak self] path in
            guard let self else { return }
            let connectionAndStatus = monitor.currentPath.connectionAndStatus
            connectionType = connectionAndStatus.0
            currentStatus = connectionAndStatus.1
        }
        monitor.start(queue: queue)
    }
    
    func cancel() {
        monitor.cancel()
    }
}
