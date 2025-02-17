//
//  UIApplication+Extension.swift
//  ADKit
//
//  Created by ray on 2025/2/14.
//

import UIKit


public extension UIApplication {
    
    var currentKeyWindow: UIWindow? {
        return windows.first {
            $0.isKeyWindow
        }
    }
    
}
