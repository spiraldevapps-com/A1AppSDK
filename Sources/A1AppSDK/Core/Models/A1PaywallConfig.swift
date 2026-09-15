//
//  A1PaywallConfig.swift
//  A1AppSDK
//

import Foundation
import UIKit

/// How a placement wants to be presented.
///
/// The two cases are not invented — they mirror what a paywall vendor actually returns.
/// A placement either carries a vendor-rendered view configuration (the dashboard's
/// paywall builder), or it carries only a JSON payload that the app renders natively.
public enum A1PaywallConfig {
    /// The vendor rendered the paywall. Present this controller as-is.
    case builder(UIViewController)
    /// No vendor UI — the app renders its own screen from this payload.
    case remoteConfig(A1PaywallPayload)
}

/// A vendor-supplied JSON payload describing a natively rendered paywall.
public struct A1PaywallPayload {
    /// Placement this payload belongs to.
    public let placement: A1Placement
    /// Locale the vendor resolved for this payload.
    public let locale: String
    /// Raw JSON exactly as configured in the dashboard.
    public let jsonString: String

    public init(placement: A1Placement, locale: String, jsonString: String) {
        self.placement = placement
        self.locale = locale
        self.jsonString = jsonString
    }

    /// Untyped access, for keys the SDK has no model for.
    public var dictionary: [String: Any]? {
        guard let data = jsonString.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }
        return object
    }

    /// Typed access.
    ///
    /// Returns `nil` rather than throwing: a malformed dashboard payload must never be able
    /// to break a paywall at runtime. Callers fall back to their built-in defaults.
    /// This mirrors the convention `AdsConfiguration` already uses for Remote Config.
    public func decode<T: Decodable>(_ type: T.Type = T.self) -> T? {
        guard let data = jsonString.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }
}
