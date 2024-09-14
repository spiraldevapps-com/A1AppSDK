//
//  AdsBannerType.swift
//  A1IOSLib
//
//  Created by Mohammad Zaid on 28/11/23.
//

import Foundation

public protocol AdsBannerType: AnyObject {
    /// Removes the banner from its superview.
    func remove()
    
    /// Show the banner ad.
    func show()
    
    func updateLayout()
}
