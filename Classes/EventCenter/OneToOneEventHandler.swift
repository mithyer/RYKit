//
//  OneToOneEvent.swift
//  RYKit
//
//  Created by ray on 2025/12/9.
//

import Foundation

// MARK: - 1对1事件
class OneToOneEventHandler<E: Event> {
    
    private weak var boundSender: AnyObject?
    private weak var boundReceiver: AnyObject?
    private var handler: ((E) -> Void)?
    
    var isSenderBound: Bool {
        return boundSender != nil
    }
    
    var isReceiverBound: Bool {
        return boundReceiver != nil && handler != nil
    }
    
    var isFullyBound: Bool {
        return isSenderBound && isReceiverBound
    }
        
    // 绑定发送者
    func bindSender(_ sender: OneToOneSender) {
        guard boundSender == nil else {
            log_event_center("⚠️ OneToOneEvent 发送者已绑定")
            return
        }
        
        self.boundSender = sender
        log_event_center("✅ 1对1事件发送者绑定成功 ")
    }
    
    // 绑定接收者
    func bindReceiver(_ receiver: OneToOneReceiver, handler: @escaping (E) -> Void) {
        guard boundReceiver == nil else {
            log_event_center("⚠️ OneToOneEvent 接收者已绑定")
            return
        }
        
        self.boundReceiver = receiver
        self.handler = handler
        log_event_center("✅ 1对1事件接收者绑定成功")
    }
    
    // 发送事件
    func send(from sender: OneToOneSender, data: E.DATA) {
        guard boundSender === sender else {
            log_event_center("⚠️ 只有绑定的发送者才能发送事")
            return
        }
        
        guard let _ = boundReceiver else {
            log_event_center("⚠️ 接收者未绑定或已释放，无法发送事件")
            return
        }
        
        let event = E(data: data, sender: sender)
        handler?(event)
    }
    
    // 解绑发送者
    func unbindSender() {
        boundSender = nil
        log_event_center("🗑️ 解绑发送者")
    }
    
    // 解绑接收者
    func unbindReceiver() {
        handler = nil
        boundReceiver = nil
        log_event_center("🗑️ 解绑接收者")
    }
    
    // 解绑所有
    func unbind() {
        unbindSender()
        unbindReceiver()
    }
    
    deinit {
        unbind()
    }
}
