//
//  SupportProvider.swift
//  A1AppSDK
//

import Foundation
import UIKit

/// Customer messaging / help desk.
public protocol SupportProvider: AnyObject {

    /// Present the support UI.
    func present(from viewController: UIViewController)

    /// Push the current user's attributes to the vendor.
    /// Called at boot and whenever pro status or identity changes.
    func updateUser(attributes: [String: Any])

    /// Forward the APNs token so the vendor can deliver push.
    func registerForPush(deviceToken: Data)

    /// Number of unread messages, for badging.
    var unreadCount: Int { get }
}

public extension SupportProvider {
    var unreadCount: Int { 0 }
    func registerForPush(deviceToken: Data) {}
}
