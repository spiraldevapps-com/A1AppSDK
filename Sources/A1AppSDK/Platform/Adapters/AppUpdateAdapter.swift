//
//  AppUpdateAdapter.swift
//  A1AppSDK
//
//  Force and optional update prompts, replacing the copy of `AppManager` each host app
//  carried. The version comparison stays in the legacy `AppUpdate`; this module owns the
//  wiring — App Store URL, the remote payload, and re-blocking on return to the foreground.
//

import Foundation
import UIKit

public final class AppUpdateAdapter: A1Module, A1LifecycleObserving {

    /// Boots with Remote Config: the payload must have landed, and a force prompt has to be
    /// able to block the UI before the user gets anywhere.
    /// Immediately AFTER remote config, not alongside it.
    ///
    /// This module reads Remote Config during `configure`, and sharing phase 300 with
    /// `RemoteConfigAdapter` made correctness depend on registration order rather than on the
    /// declared ordering — which is exactly the kind of implicit coupling phases exist to remove.
    public var phase: A1BootPhase { .custom(after: .remoteConfig) }

    private let lock = NSLock()
    private var didReportMissingStoreURL = false
    private var analytics: AnalyticsProvider?

    public init() {}

    // MARK: - A1Module

    public func configure(context: A1ModuleContext) {
        analytics = context.analytics
        AppUpdate.shared.appStoreURL = context.configuration.appStoreURL

        // Best effort seed from the last activated payload, so a force prompt can block on
        // launch instead of waiting for this launch's fetch. `apply` overrides it.
        if let cached = A1SDK.shared.module(RemoteConfigAdapter.self)?
            .decode(VersionConfig.self, forKey: context.configuration.versionConfigKey) {
            AppUpdate.shared.versionConfig = cached
        }
    }

    // MARK: - Prompts

    /// Apply a freshly fetched payload. Passing `nil` for the URL keeps the one from
    /// `A1Configuration.appStoreURL`.
    public func apply(_ config: VersionConfig, appStoreURL: String? = nil) {
        AppUpdate.shared.configureAppUpdate(url: appStoreURL ?? AppUpdate.shared.appStoreURL ?? "",
                                            config: config)
    }

    /// Show whichever prompt is due. Force wins; the optional prompt appears at most once per
    /// session. No-ops silently until a payload has been applied.
    public func checkForUpdate(canShowOptional: Bool = true) {
        // `connectedScenes` and the presenter are main-thread only; an app calling this from
        // a fetch completion on another queue must not have to know that.
        guard Thread.isMainThread else {
            DispatchQueue.main.async { [weak self] in self?.checkForUpdate(canShowOptional: canShowOptional) }
            return
        }
        guard canPresent else { return }
        reportMissingStoreURLOnce()
        AppUpdate.shared.checkUpdate(canCheckOptionalUpdate: canShowOptional)
    }

    /// `true` while an update alert is on screen. Tracks the alert itself, so an alert torn
    /// down with its presenter counts as gone and the foreground re-check keeps working.
    ///
    /// The presenter runs inside a `DispatchQueue.main.async`, so this only turns true on the
    /// run loop turn after `checkForUpdate` — read it later, not on the same turn.
    public var isPromptShowing: Bool { AppUpdate.shared.isPopupShowing }

    // MARK: - A1LifecycleObserving

    /// Tapping "Update Now" dismisses the force prompt and leaves for the App Store. If the
    /// user comes back without updating, the app has to block again. Force only — the optional
    /// prompt stays a once-per-session nudge.
    public func applicationDidBecomeActive(_ application: UIApplication) {
        guard !AppUpdate.shared.isPopupShowing else { return }
        checkForUpdate(canShowOptional: false)
    }

    // MARK: - Presentation

    /// Nothing to present into yet (no window): skip this check, the next foreground retries.
    private var canPresent: Bool {
        UIApplication.shared.connectedScenes.contains { scene in
            (scene as? UIWindowScene)?.windows.contains { $0.rootViewController != nil } == true
        }
    }

    /// An empty URL leaves "Update Now" doing nothing — a silent misconfiguration worth one report.
    private func reportMissingStoreURLOnce() {
        // Only worth reporting when there is a version requirement that a prompt would act on.
        // An app that never configured force-update must get an inert module, not a non-fatal
        // on every launch — that noise reached Crashlytics and AppMetrica in Scanner.
        guard let config = AppUpdate.shared.versionConfig,
              !(config.minVersion.isEmpty && config.stableVersion.isEmpty),
              AppUpdate.shared.appStoreURL?.isEmpty != false else { return }
        lock.lock()
        let alreadyReported = didReportMissingStoreURL
        didReportMissingStoreURL = true
        lock.unlock()

        guard !alreadyReported else { return }
        analytics?.reportError(.app_update_configuration_error,
                               message: "No App Store URL — the update prompt cannot open the store.",
                               parameters: nil)
    }
}
