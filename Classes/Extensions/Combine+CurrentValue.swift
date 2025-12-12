//
//  Combine+CurrentValue.swift
//  RYKit
//
//  Created by mao rui on 2025/12/12.
//

import Combine
import Foundation

// MARK: - CurrentValue Property Wrapper
@propertyWrapper
struct CurrentValue<Value> {
    private let subject: CurrentValueSubject<Value, Never>
    
    var wrappedValue: Value {
        get { subject.value }
        set { subject.send(newValue) }
    }
    
    var projectedValue: CurrentValueSubject<Value, Never> {
        subject
    }
    
    init(wrappedValue: Value) {
        subject = CurrentValueSubject(wrappedValue)
    }
}
