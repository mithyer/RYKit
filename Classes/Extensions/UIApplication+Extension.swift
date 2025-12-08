//
//  UIApplication+Extension.swift
//  RYKit
//
//  Created by ray on 2025/2/14.
//

import UIKit


public extension UIApplication {
    
    var currentKeyWindow: UIWindow? {
        return connectedScenes.compactMap {
            $0 as? UIWindowScene
        }.flatMap {
            $0.windows
        }.first {
            $0.isKeyWindow
        }
    }
    
}
