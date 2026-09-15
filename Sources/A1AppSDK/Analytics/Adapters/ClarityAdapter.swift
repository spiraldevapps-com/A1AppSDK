//
//  ClarityAdapter.swift
//  A1AppSDK
//

import Foundation
import Clarity
import FirebaseCore
import FirebaseAnalytics
import FirebaseCrashlytics

/// Microsoft Clarity session recording.
///
/// Not registered as an `AnalyticsProvider`. Clarity does expose `sendCustomEvent` and
/// `setCustomTag`, so it *could* take the event stream, but it does not receive it today —
/// wiring it in would change what every existing event reaches, which is a deliberate
/// analytics decision rather than a refactor. `sendCustomEvent(_:)` / `setTag(_:_:)` below
/// make the capability available without changing current behaviour.
public final class ClarityAdapter: A1Module {

    public var phase: A1BootPhase { .analytics }

    private var isActive = false
    private var identityToken: A1ObservationToken?
    /// Reporting channel captured at boot. Weak: the dispatcher is owned by `A1SDK`.
    private weak var analytics: AnalyticsProvider?
    /// The Firebase cross-link warning is emitted once, not on every session start.
    private var didReportMissingFirebase = false

    public init() {}

    public func configure(context: A1ModuleContext) {
        analytics = context.analytics

        guard let projectID = context.configuration.clarityProjectID, !projectID.isEmpty else { return }

        let config = ClarityConfig(
            projectId: projectID,
            // Empty on a first launch; corrected by the identity observer below.
            userId: context.identity.userID.isEmpty ? nil : context.identity.userID,
            logLevel: context.configuration.isLoggingEnabled ? .verbose : .none,
            applicationFramework: .native
        )
        isActive = ClaritySDK.initialize(config: config)

        guard isActive else {
            context.analytics.reportError("a1sdk_clarity_init_failed",
                                          message: "ClaritySDK.initialize returned false",
                                          parameters: ["projectId": projectID])
            return
        }

        identityToken = context.identity.observe { [weak self] userID in
            guard let self, self.isActive, !userID.isEmpty else { return }
            ClaritySDK.setCustomUserId(userID)
        }

        bindSessionToFirebase()
    }

    /// Cross-links a Clarity session with Firebase, so a Crashlytics report can be traced
    /// back to a session recording.
    ///
    /// Logged to Firebase Analytics directly rather than through the dispatcher: this event
    /// reaches only Firebase today, and fanning it out to AppMetrica and Meta would change
    /// what the analytics dashboards receive.
    private func bindSessionToFirebase() {
        ClaritySDK.setOnSessionStartedCallback { [weak self] _ in
            DispatchQueue.main.async {
                guard let url = ClaritySDK.getCurrentSessionUrl() else { return }

                // Firebase boots in an earlier phase than this module, so it is normally
                // present. A host app registering a subset of modules is the case that
                // makes this a guard rather than an assumption — Firebase traps when its
                // default app was never configured.
                guard FirebaseApp.app() != nil else {
                    self?.reportMissingFirebaseOnce()
                    return
                }

                Analytics.logEvent("session_started", parameters: ["clarity_links": url])
                // Resolved at callback time, not boot time: entitlement is established in a
                // later phase than this module, so reading it earlier would always be false.
                let isPro = A1SDK.shared.subscriptions?.isPro ?? false
                Crashlytics.crashlytics().setCustomValue(isPro, forKey: "isPro")
                Crashlytics.crashlytics().setCustomValue(url, forKey: "claritySessionLink")
            }
        }
    }

    /// Main-queue only — called from the session callback above.
    private func reportMissingFirebaseOnce() {
        guard !didReportMissingFirebase else { return }
        didReportMissingFirebase = true
        analytics?.reportError(
            "a1sdk_clarity_firebase_unavailable",
            message: "FirebaseApp is not configured — Clarity session link was not cross-linked",
            parameters: nil
        )
    }

    // MARK: - Optional passthrough

    /// Current session replay URL, if a session is running.
    public var currentSessionURL: String? {
        guard isActive else { return nil }
        return ClaritySDK.getCurrentSessionUrl()
    }

    @discardableResult
    public func sendCustomEvent(_ value: String) -> Bool {
        guard isActive else { return false }
        return ClaritySDK.sendCustomEvent(value: value)
    }

    @discardableResult
    public func setTag(_ key: String, _ value: String) -> Bool {
        guard isActive else { return false }
        return ClaritySDK.setCustomTag(key: key, value: value)
    }

    public func setCurrentScreen(_ name: String?) {
        guard isActive else { return }
        ClaritySDK.setCurrentScreenName(name)
    }
}
