//
//  ConsentAdapter.swift
//  A1AppSDK
//
//  Google UMP (GDPR) consent, as a module.
//

import Foundation
import UIKit

public final class ConsentAdapter: A1Module {

    /// Runs *before* `.advertising`.
    ///
    /// Consent must be resolved before ads are configured or loaded — the Mobile Ads SDK
    /// begins preloading as soon as it starts, and preloading ahead of consent in the EEA
    /// is exactly what the UMP flow exists to prevent. The gap in the phase numbering is
    /// deliberate, not arbitrary.
    public var phase: A1BootPhase { A1BootPhase.custom(after: .monetization, offset: 90) }

    /// Computed, never stored: reaching `ConsentManager.shared` from a stored-property
    /// initialiser would build vendor-facing state at *construction* time, and
    /// `A1SDK.standardModules()` constructs every module in one array literal long before
    /// any of them is configured.
    private var manager: ConsentManager { ConsentManager.shared }

    private var analytics: AnalyticsProvider?
    private let lock = NSLock()
    private var booted = false
    private var resolved = false
    private var waiters: [() -> Void] = []

    public init() {}

    public func configure(context: A1ModuleContext) {
        analytics = context.analytics
        lock.lock(); booted = true; lock.unlock()
        manager.gatherConsent { [weak self] in self?.markResolved() }
    }

    /// `true` once `configure(context:)` has run. Every UMP call is gated on it, so a host
    /// app touching this module before `A1SDK.configure(with:)` cannot start the vendor.
    private var isBooted: Bool {
        lock.lock(); defer { lock.unlock() }
        return booted
    }

    /// `true` once the consent round-trip has finished, successfully or not.
    public var isResolved: Bool {
        lock.lock(); defer { lock.unlock() }
        return resolved
    }

    /// Run `work` once consent has been resolved — immediately if it already has.
    ///
    /// This is the mechanism that actually enforces "no ad loading before consent".
    /// The phase gap between this module and the ads module orders `configure` calls but
    /// cannot, on its own, wait for an asynchronous network round-trip.
    public func whenResolved(_ work: @escaping () -> Void) {
        lock.lock()
        if resolved { lock.unlock(); work(); return }
        waiters.append(work)
        lock.unlock()
    }

    private func markResolved() {
        lock.lock()
        guard !resolved else { lock.unlock(); return }
        resolved = true
        let pending = waiters
        waiters.removeAll()
        lock.unlock()
        pending.forEach { $0() }
    }

    /// Whether a privacy-options entry point must be shown (EEA users who already consented).
    ///
    /// Safe to read before boot: UMP has not been asked anything yet, so the answer is
    /// `false` rather than a query that would spin up `UMPConsentInformation`.
    public var isPrivacyOptionsRequired: Bool {
        guard isBooted else { return false }
        return manager.isPrivacyOptionsRequired
    }

    /// Present the consent form, then reconfigure ads according to the outcome.
    public func presentConsentForm(from viewController: UIViewController,
                                   adConfiguration: AdsConfiguration,
                                   isPro: Bool,
                                   completion: @escaping () -> Void) {
        guard isBooted else {
            analytics?.reportError("consent_not_configured",
                                   message: "presentConsentForm called before A1SDK.configure(with:)",
                                   parameters: nil)
            completion()
            return
        }

        manager.showGDPR(from: viewController,
                         adConfig: adConfiguration,
                         isPro: isPro,
                         completionHandler: completion)
    }
}
