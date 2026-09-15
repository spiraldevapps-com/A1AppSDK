//
//  NativePaywallParser.swift
//  A1AppSDK
//
//  Decodes the JSON a placement carries when it has no vendor-rendered UI, so an app can
//  build its own paywall screen from dashboard-controlled content.
//

import Foundation

/// A natively rendered paywall's content.
///
/// Every field is optional with a safe default and decoding never throws — the same
/// convention `AdsConfiguration` uses for Remote Config. A malformed or partial payload
/// from the dashboard must never be able to break a paywall; the app falls back to its
/// own copy for anything missing.
public struct A1NativePaywall: Decodable {

    public struct Product: Decodable {
        public let identifier: String
        public let title: String?
        public let subtitle: String?
        public let badge: String?
        public let isPreselected: Bool

        enum CodingKeys: String, CodingKey {
            case identifier = "product_id"
            case title, subtitle, badge
            case isPreselected = "preselected"
        }

        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            identifier = try c.decodeIfPresent(String.self, forKey: .identifier) ?? ""
            title = try c.decodeIfPresent(String.self, forKey: .title)
            subtitle = try c.decodeIfPresent(String.self, forKey: .subtitle)
            badge = try c.decodeIfPresent(String.self, forKey: .badge)
            isPreselected = try c.decodeIfPresent(Bool.self, forKey: .isPreselected) ?? false
        }
    }

    public let title: String?
    public let subtitle: String?
    public let features: [String]
    public let products: [Product]
    public let ctaTitle: String?
    public let footerText: String?
    /// Layout/A-B variant name, for apps that ship more than one native design.
    public let variant: String?
    public let showsCloseButton: Bool

    enum CodingKeys: String, CodingKey {
        case title, subtitle, features, products, variant
        case ctaTitle = "cta_title"
        case footerText = "footer_text"
        case showsCloseButton = "show_close_button"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        title = try c.decodeIfPresent(String.self, forKey: .title)
        subtitle = try c.decodeIfPresent(String.self, forKey: .subtitle)
        features = try c.decodeIfPresent([String].self, forKey: .features) ?? []
        products = try c.decodeIfPresent([Product].self, forKey: .products) ?? []
        ctaTitle = try c.decodeIfPresent(String.self, forKey: .ctaTitle)
        footerText = try c.decodeIfPresent(String.self, forKey: .footerText)
        variant = try c.decodeIfPresent(String.self, forKey: .variant)
        showsCloseButton = try c.decodeIfPresent(Bool.self, forKey: .showsCloseButton) ?? true
    }
}

/// Turns a `.remoteConfig` payload into something renderable.
public enum NativePaywallParser {

    /// Parse into the SDK's default shape.
    ///
    /// Returns `nil` only when the payload is not valid JSON at all — every individual
    /// field tolerates being absent.
    public static func parse(_ payload: A1PaywallPayload) -> A1NativePaywall? {
        payload.decode(A1NativePaywall.self)
    }

    /// Parse into an app-defined shape, for apps whose dashboard payload does not match
    /// `A1NativePaywall`. The SDK does not need to know the schema to be useful here.
    public static func parse<T: Decodable>(_ payload: A1PaywallPayload, as type: T.Type) -> T? {
        payload.decode(T.self)
    }
}
