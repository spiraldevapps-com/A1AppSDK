//
//  A1Configuration.swift
//  A1AppSDK
//
//  Everything the host app supplies. Keys stay in the app (they differ per app and some
//  are per-environment); the SDK owns what is done with them.
//

import Foundation

public struct A1Configuration {

    // MARK: - Analytics

    /// AppMetrica API key. When nil or empty, AppMetrica is skipped entirely —
    /// preserving the existing `EventManager` behaviour.
    public var appMetricaAPIKey: String?
    public var isFirebaseAnalyticsEnabled: Bool
    public var isMetaAnalyticsEnabled: Bool

    // MARK: - Session recording

    /// Microsoft Clarity project id. Nil disables session recording.
    public var clarityProjectID: String?

    // MARK: - Monetization

    /// Adapty (or successor vendor) public SDK key.
    public var subscriptionAPIKey: String?
    /// Entitlement checked for premium. Dashboard-defined; defaults to the value all apps use today.
    public var premiumAccessLevel: String
    /// Placements warmed at launch so presentation is instant.
    public var prefetchedPlacements: [A1Placement]
    /// Locale for paywall content, e.g. "en", "pt-BR", "es-419".
    /// Nil lets the vendor pick its default. Apps that normalise regional variants
    /// (mapping "en-AU" to "en", say) resolve that themselves and pass the result here.
    public var paywallLocale: String?

    // MARK: - Support

    public struct SupportCredentials {
        public let apiKey: String
        public let appID: String
        public init(apiKey: String, appID: String) {
            self.apiKey = apiKey
            self.appID = appID
        }
    }
    public var support: SupportCredentials?

    // MARK: - Platform

    /// Apple Search Ads attribution. Fetched once per install.
    public var isSearchAdsAttributionEnabled: Bool
    /// ATT. When false the SDK never prompts and reports `.denied`.
    public var isTrackingEnabled: Bool
    /// Firebase Performance traces. Nil leaves the Info.plist setting alone.
    public var isPerformanceMonitoringEnabled: Bool?
    /// Emit an analytics event on connectivity changes. Noisy — off by default.
    public var isNetworkStatusLoggingEnabled: Bool
    /// StoreKit product ids that grant entitlement. Empty means any entitlement counts.
    public var entitlementProductIDs: [String]
    /// Entitlement to assume on the very first launch after adopting the SDK.
    ///
    /// The SDK caches entitlement under its own key, which is absent on an upgrade — so without
    /// this an existing subscriber is treated as free until the vendor answers. Pass the app's
    /// own persisted pro flag here; it is used only when the SDK has no cached value of its own.
    public var initialEntitlement: Bool?
    /// Remote Config key holding the `VersionConfig` payload.
    public var versionConfigKey: String

    // MARK: - App update

    /// Used by the force/optional update prompts.
    public var appStoreURL: String?

    // MARK: - Diagnostics

    /// Emit SDK boot diagnostics. Leave off in release.
    public var isLoggingEnabled: Bool

    // MARK: - Extension point

    /// Free-form values for host-app modules. Keeps custom frameworks from having to
    /// fork this type just to carry one key.
    public var custom: [String: Any]

    public init(appMetricaAPIKey: String? = nil,
                isFirebaseAnalyticsEnabled: Bool = true,
                isMetaAnalyticsEnabled: Bool = true,
                clarityProjectID: String? = nil,
                subscriptionAPIKey: String? = nil,
                premiumAccessLevel: String = "premium",
                prefetchedPlacements: [A1Placement] = [],
                paywallLocale: String? = nil,
                support: SupportCredentials? = nil,
                isSearchAdsAttributionEnabled: Bool = true,
                isTrackingEnabled: Bool = true,
                isPerformanceMonitoringEnabled: Bool? = nil,
                isNetworkStatusLoggingEnabled: Bool = false,
                entitlementProductIDs: [String] = [],
                initialEntitlement: Bool? = nil,
                versionConfigKey: String = "version_config",
                appStoreURL: String? = nil,
                isLoggingEnabled: Bool = false,
                custom: [String: Any] = [:]) {
        self.appMetricaAPIKey = appMetricaAPIKey
        self.isFirebaseAnalyticsEnabled = isFirebaseAnalyticsEnabled
        self.isMetaAnalyticsEnabled = isMetaAnalyticsEnabled
        self.clarityProjectID = clarityProjectID
        self.subscriptionAPIKey = subscriptionAPIKey
        self.premiumAccessLevel = premiumAccessLevel
        self.prefetchedPlacements = prefetchedPlacements
        self.paywallLocale = paywallLocale
        self.support = support
        self.isSearchAdsAttributionEnabled = isSearchAdsAttributionEnabled
        self.isTrackingEnabled = isTrackingEnabled
        self.isPerformanceMonitoringEnabled = isPerformanceMonitoringEnabled
        self.isNetworkStatusLoggingEnabled = isNetworkStatusLoggingEnabled
        self.entitlementProductIDs = entitlementProductIDs
        self.initialEntitlement = initialEntitlement
        self.versionConfigKey = versionConfigKey
        self.appStoreURL = appStoreURL
        self.isLoggingEnabled = isLoggingEnabled
        self.custom = custom
    }
}
