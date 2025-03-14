//
//  UserDefaults+Extension.swift
//  Pods
//
//  Created by ray on 2025/3/14.
//

public extension UserDefaults {
    
    struct WithKeyExtended {
        
        public let extended: (_ originKey: String) -> String
        
        public init(_ extended: @escaping (_: String) -> String) {
            self.extended = extended
        }
        
        public func set(_ value: Any?, forKey key: String) {
            UserDefaults.standard.set(value, forKey: extended(key))
        }
        
        public func object(forKey key: String) -> Any? {
            UserDefaults.standard.object(forKey: extended(key))
        }
        
        public func bool(forKey key: String) -> Bool {
            UserDefaults.standard.bool(forKey: extended(key))
        }
        
        public func string(forKey key: String) -> String? {
            UserDefaults.standard.string(forKey: extended(key))
        }
    }
}
