//
//  AnalyticsProvider.swift
//  A1AppSDK
//

import Foundation

/// A single analytics destination.
///
/// `AnalyticsDispatcher` is itself an `AnalyticsProvider` that composes several of these,
/// so callers never know or care how many sinks are attached.
public protocol AnalyticsProvider: AnyObject {

    /// Human-readable sink name, for debug screens.
    var providerName: String { get }

    /// Send one event.
    func log(_ event: A1Event)

    /// Set a user-scoped property.
    func setUserProperty(_ value: String?, for name: String)

    /// Associate subsequent events with a user id. Called again whenever identity resolves.
    func identify(userID: String)

    /// Report a non-fatal error.
    func reportError(_ name: String, message: String, parameters: [String: Any]?)
}

public extension AnalyticsProvider {
    var providerName: String { String(describing: type(of: self)) }
    func setUserProperty(_ value: String?, for name: String) {}
    func identify(userID: String) {}
    func reportError(_ name: String, message: String, parameters: [String: Any]?) {}
}
