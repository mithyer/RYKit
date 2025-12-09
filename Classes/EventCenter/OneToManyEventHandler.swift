//
//  OneToManyEvent.swift
//  RYKit
//
//  Created by ray on 2025/12/9.
//

import Foundation

// MARK: - 1对多事件
class OneToManyEventHandler<E: Event> {

    private weak var boundSender: OneToManySender?
    private var boundReceivers: [String: (EventReceiverHolder, (E) -> Void)] = [:]
        
    // 绑定发送者
    func bindSender(_ sender: OneToManySender) {
        guard boundSender == nil else {
            log_event_center("⚠️ OneToManyEvent 发送者已绑定")
            return
        }
        self.boundSender = sender
    }
    
    // 添加接收者
    func addReceiver(_ receiver: OneToManyReceiver, handler: @escaping (E) -> Void) {
        let receiverId = receiver.oneToManyReceiverId
        guard nil == boundReceivers[receiverId]?.0.receiver else {
            boundReceivers.removeValue(forKey: receiverId)
            return
        }
        
        let receiverInfo = EventReceiverHolder(receiver: receiver, id: receiverId)
        boundReceivers[receiverId] = (receiverInfo, handler)
    }
    
    // 移除接收者s
    func removeReceiver(_ receiver: OneToManyReceiver) {
        let id = receiver.oneToManyReceiverId
        boundReceivers.removeValue(forKey: id)
    }
    
    // 发送事件
    func send(from sender: OneToManySender, data: E.DATA) {
        guard boundSender === sender else {
            log_event_center("⚠️ 只有绑定的发送者才能发送事件")
            return
        }
        
        // 清理已释放的接收者
        boundReceivers = boundReceivers.compactMapValues { receiver in
            if receiver.0.receiver == nil {
                return nil
            }
            return receiver
        }
        
        guard boundReceivers.count > 0 else {
            log_event_center("⚠️ 没有可用的接收者")
            return
        }
        
        var event = E(data: data, sender: sender)
        for (_, holder) in boundReceivers {
            let receiver = holder.0.receiver
            // 验证接收者是否还存在
            guard receiver != nil else {
                return
            }
            // 验证发送者
            guard boundSender === sender else {
                log_event_center("⚠️ 事件发送者不匹配")
                return
            }
            event.receiver = receiver
            holder.1(event)
        }
    }
    
    // 解绑所有
    func unbindAll() {
        boundReceivers.removeAll()
        boundSender = nil
    }
    
    deinit {
        unbindAll()
    }
}
