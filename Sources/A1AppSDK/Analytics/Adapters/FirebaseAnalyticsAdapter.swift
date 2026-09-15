//
//  FirebaseAnalyticsAdapter.swift
//  A1AppSDK
//

import Foundation
import FirebaseCore
import FirebaseAnalytics
import FirebaseCrashlytics
import StoreKit

/// Firebase Analytics event sink, with non-fatals routed to Crashlytics.
public final class FirebaseAnalyticsAdapter: A1Module, AnalyticsProvider {

    public var phase: A1BootPhase { .analytics }
    public var providerName: String { "Firebase" }

    private var isEnabled = false
    private var identityToken: A1ObservationToken?

    public init() {}

    public func configure(context: A1ModuleContext) {
        isEnabled = context.configuration.isFirebaseAnalyticsEnabled
        guard isEnabled else { return }

        // The bootstrap phase runs before this one, so a missing default app means
        // FirebaseCoreAdapter was not registered (or its own configure bailed out).
        // Report it once here; every entry point below then degrades to a no-op instead
        // of trapping inside Firebase.
        if !isFirebaseConfigured {
            context.analytics.reportError(
                "a1sdk_firebase_unavailable",
                message: "FirebaseApp is not configured — Firebase Analytics events will be dropped",
                parameters: nil
            )
        }

        identityToken = context.identity.observe { [weak self] userID in
            self?.identify(userID: userID)
        }
    }

    /// Firebase raises `FIRAppNotConfigured` when its default app is missing, and a host app
    /// may register a subset of modules, or touch a sink before `A1SDK.configure(with:)` runs.
    /// Checked per call rather than cached so a late `FirebaseApp.configure()` still recovers.
    private var isFirebaseConfigured: Bool { FirebaseApp.app() != nil }

    private var isReady: Bool { isEnabled && isFirebaseConfigured }

    public func log(_ event: A1Event) {
        guard isReady else { return }
        Analytics.logEvent(event.name, parameters: event.parameters)
    }

    public func setUserProperty(_ value: String?, for name: String) {
        guard isReady else { return }
        Analytics.setUserProperty(value, forName: name)
    }

    public func identify(userID: String) {
        guard isReady, !userID.isEmpty else { return }
        Analytics.setUserID(userID)
        Crashlytics.crashlytics().setUserID(userID)
    }

    /// Firebase's purchase-revenue hook.
    ///
    /// Lives here rather than in the monetization adapter so `Monetization/` never has to
    /// import Firebase — the Adapty adapter reaches this through `A1SDK.shared.module(_:)`.
    @available(iOS 15.0, *)
    public func logTransaction(_ transaction: StoreKit.Transaction) {
        guard isReady else { return }
        Analytics.logTransaction(transaction)
    }

    public func reportError(_ name: String, message: String, parameters: [String: Any]?) {
        // Deliberately silent when Firebase is absent: this sink cannot report its own
        // unavailability through itself, and `configure` already announced it once.
        guard isReady else { return }
        var info: [String: Any] = [NSLocalizedDescriptionKey: message]
        parameters?.forEach { info[$0.key] = $0.value }
        Crashlytics.crashlytics().record(error: NSError(domain: name, code: -1, userInfo: info))
    }
}
