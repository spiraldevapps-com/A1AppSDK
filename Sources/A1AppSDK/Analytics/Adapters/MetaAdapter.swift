//
//  MetaAdapter.swift
//  A1AppSDK
//

import Foundation
import UIKit
import FBSDKCoreKit

/// Meta (Facebook) App Events sink.
///
/// Boots at `.foundation` because the Meta SDK must receive `didFinishLaunching` with the
/// original launch options before anything else runs.
///
/// `configure(context:)` therefore only reads a flag: the vendor is not usable until
/// `ApplicationDelegate.application(_:didFinishLaunchingWithOptions:)` has initialised it,
/// which happens *after* boot. Anything logged in between is held and flushed on
/// initialisation rather than pushed into an uninitialised SDK.
public final class MetaAdapter: A1Module, AnalyticsProvider, A1LifecycleObserving {

    /// Boot produces a handful of events; the cap only exists so an app that never forwards
    /// `didFinishLaunching` cannot grow this without bound.
    private static let maxPendingEvents = 100

    public var phase: A1BootPhase { .foundation }
    public var providerName: String { "Meta" }

    private let lock = NSLock()
    private var isEnabled = false
    /// `true` once the Meta SDK has actually been handed `didFinishLaunching`.
    private var isSDKInitialized = false
    private var pendingEvents: [A1Event] = []
    private var pendingUserID: String?

    public init() {}

    public func configure(context: A1ModuleContext) {
        lock.lock()
        isEnabled = context.configuration.isMetaAnalyticsEnabled
        lock.unlock()
    }

    /// Run `work` once the Meta SDK is actually initialised — immediately if it already is.
    ///
    /// `anonymousID` is empty until `applicationDidFinishLaunching` reaches this module, so a
    /// caller reading it during boot silently gets "" and breaks Meta purchase attribution.
    public func whenInitialized(_ work: @escaping (String) -> Void) {
        lock.lock()
        if isEnabled, isSDKInitialized { lock.unlock(); work(anonymousID); return }
        pendingInitialization.append(work)
        lock.unlock()
    }

    private var pendingInitialization: [(String) -> Void] = []

    /// Meta's anonymous id, used for purchase attribution by the monetization adapter.
    ///
    /// Empty until the Meta SDK is initialised. Reading `AppEvents.shared` before that spins
    /// up vendor state at an arbitrary moment — including before `A1SDK.configure(with:)` —
    /// which is precisely what a public accessor must not do.
    public var anonymousID: String {
        lock.lock()
        let ready = isEnabled && isSDKInitialized
        lock.unlock()
        guard ready else { return "" }
        return AppEvents.shared.anonymousID
    }

    // MARK: - AnalyticsProvider

    public func log(_ event: A1Event) {
        lock.lock()
        guard isEnabled else { lock.unlock(); return }
        guard isSDKInitialized else {
            if pendingEvents.count < Self.maxPendingEvents { pendingEvents.append(event) }
            lock.unlock()
            return
        }
        lock.unlock()

        send(event)
    }

    public func identify(userID: String) {
        guard !userID.isEmpty else { return }

        lock.lock()
        guard isEnabled else { lock.unlock(); return }
        guard isSDKInitialized else {
            pendingUserID = userID
            lock.unlock()
            return
        }
        lock.unlock()

        AppEvents.shared.userID = userID
    }

    /// The vendor call itself. Event names and parameter values are unchanged.
    private func send(_ event: A1Event) {
        guard let parameters = event.parameters else {
            AppEvents.shared.logEvent(AppEvents.Name(event.name), parameters: nil)
            return
        }

        // Same mapping the previous EventManager used, but built with `uniquingKeysWith:`
        // instead of `uniqueKeysWithValues:` — the latter traps at runtime if two keys
        // collapse to the same ParameterName. No event name or value changes.
        let mapped = Dictionary(
            parameters.map { (AppEvents.ParameterName($0.key), $0.value) },
            uniquingKeysWith: { _, latest in latest }
        )
        AppEvents.shared.logEvent(AppEvents.Name(event.name), parameters: mapped)
    }

    // MARK: - A1LifecycleObserving

    public func applicationDidFinishLaunching(_ application: UIApplication,
                                              launchOptions: [UIApplication.LaunchOptionsKey: Any]?) {
        lock.lock()
        guard isEnabled else { lock.unlock(); return }
        lock.unlock()

        ApplicationDelegate.shared.application(application, didFinishLaunchingWithOptions: launchOptions)

        lock.lock()
        isSDKInitialized = true
        let replay = pendingEvents
        let userID = pendingUserID
        let waiting = pendingInitialization
        pendingEvents.removeAll()
        pendingUserID = nil
        pendingInitialization.removeAll()
        lock.unlock()

        if let userID, !userID.isEmpty { AppEvents.shared.userID = userID }
        for event in replay { send(event) }
        // Fired outside the lock: callers use this to hand the id to other vendors.
        waiting.forEach { $0(anonymousID) }
    }

    public func applicationDidBecomeActive(_ application: UIApplication) {
        lock.lock()
        let ready = isEnabled && isSDKInitialized
        lock.unlock()
        guard ready else { return }
        AppEvents.shared.activateApp()
    }

    public func application(_ application: UIApplication,
                            open url: URL,
                            options: [UIApplication.OpenURLOptionsKey: Any]) -> Bool {
        lock.lock()
        let ready = isEnabled && isSDKInitialized
        lock.unlock()
        guard ready else { return false }

        return ApplicationDelegate.shared.application(
            application,
            open: url,
            sourceApplication: options[.sourceApplication] as? String,
            annotation: options[.annotation]
        )
    }
}
