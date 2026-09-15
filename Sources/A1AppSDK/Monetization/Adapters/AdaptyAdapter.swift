//
//  AdaptyAdapter.swift
//  A1AppSDK
//
//  Adapty behind `SubscriptionProvider`. No Adapty type crosses this file's boundary —
//  that is what makes a vendor swap a change here and nowhere else.
//

import Foundation
import UIKit
import Adapty
import AdaptyUI

public final class AdaptyAdapter: NSObject, A1Module, SubscriptionProvider, @unchecked Sendable {

    public var phase: A1BootPhase { .monetization }

    // MARK: - State

    private let lock = NSLock()
    private var cachedPaywalls: [String: (controller: AdaptyPaywallController, paywall: AdaptyPaywall)] = [:]
    /// Callbacks keyed by the controller presenting them, so two placements shown in
    /// sequence cannot deliver each other's callbacks.
    private var activeCallbacks: [ObjectIdentifier: A1PaywallCallbacks] = [:]
    /// Guards `onDismiss` against firing twice for one presentation.
    private var dismissedControllers: Set<ObjectIdentifier> = []
    private var entitlementObservers: [UUID: (Bool) -> Void] = [:]

    /// Last known entitlement, persisted across launches.
    ///
    /// Without this the adapter starts every launch at `false` and publishes that to observers
    /// before Adapty's async profile call returns — demoting a paying user to free on every cold
    /// launch, and for the whole session when the device is offline. The host app persists this
    /// value too, so an unresolved `false` would overwrite the real answer on disk.
    private static let entitlementCacheKey = "com.a1appsdk.entitlement.isPro"
    private var proFlag = UserDefaults.standard.bool(forKey: entitlementCacheKey)
    /// `true` once the vendor has actually answered at least once this launch.
    private var hasResolvedEntitlement = false
    /// `true` once `Adapty.activate` has been issued. Nothing may reach Adapty before that:
    /// `A1SDK.standardModules()` constructs this adapter long before `configure(context:)`
    /// runs, and a host app can call any of these methods in between.
    private var activated = false

    private var accessLevel = "premium"
    private var locale: String?
    private var analytics: AnalyticsProvider?
    private var identityToken: A1ObservationToken?

    public override init() { super.init() }

    // MARK: - A1Module

    public func configure(context: A1ModuleContext) {
        // Set before the key check so a module registered without a subscription key can
        // still report the calls it has to refuse.
        analytics = context.analytics

        guard let apiKey = context.configuration.subscriptionAPIKey, !apiKey.isEmpty else { return }

        // No SDK cache yet (first launch after adopting the SDK) — trust the app's own flag
        // rather than defaulting a paying user to free.
        if UserDefaults.standard.object(forKey: Self.entitlementCacheKey) == nil,
           let seed = context.configuration.initialEntitlement {
            withLock { proFlag = seed }
            UserDefaults.standard.set(seed, forKey: Self.entitlementCacheKey)
        }

        accessLevel = context.configuration.premiumAccessLevel
        locale = context.configuration.paywallLocale

        Adapty.logLevel = context.configuration.isLoggingEnabled ? .verbose : .error

        // Empty on a first launch — Adapty wants nil rather than "" for an unknown user.
        let userID = context.identity.userID

        // Raised *before* the call, not in its completion: Adapty queues work issued after
        // `activate` returns, and the completion below itself calls back into this adapter.
        isActivated = true

        Adapty.activate(apiKey, customerUserId: userID.isEmpty ? nil : userID) { [weak self] error in
            guard let self else { return }

            if let error {
                self.analytics?.reportError("adapty_configuration_error",
                                            message: error.localizedDescription,
                                            parameters: nil)
            } else {
                AdaptyUI.activate()
                self.analytics?.log("adapty_configuration_successful")
            }

            // Run regardless of activation error, matching existing behaviour: a cached
            // profile may still resolve entitlement while the network is unavailable.
            self.refreshEntitlement(completion: nil)
            self.prefetch(context.configuration.prefetchedPlacements)
        }

        identityToken = context.identity.observe { [weak self] userID in
            guard let self, !userID.isEmpty else { return }
            Adapty.identify(userID) { error in
                guard let error else { return }
                self.analytics?.reportError("adapty_identify_error",
                                            message: error.localizedDescription,
                                            parameters: nil)
            }
        }
    }

    // MARK: - Entitlement

    /// Cached flag only — no vendor call. Safe and cheap to read before boot, which host
    /// view controllers do constantly; `false` until the profile resolves.
    public var isPro: Bool { withLock { proFlag } }

    private var isActivated: Bool {
        get { withLock { activated } }
        set { withLock { activated = newValue } }
    }

    /// A call that arrived before Adapty was activated. Degrade quietly, never crash.
    private func reportInactive(_ operation: String) {
        analytics?.reportError("adapty_not_activated",
                               message: "\(operation) called before Adapty was activated",
                               parameters: nil)
    }

    public func refreshEntitlement(completion: ((Bool) -> Void)?) {
        guard isActivated else {
            reportInactive("refreshEntitlement")
            completion?(isPro)
            return
        }

        Adapty.getProfile { [weak self] result in
            guard let self else { return }
            switch result {
            case let .success(profile):
                completion?(self.applyEntitlement(from: profile))
            case let .failure(error):
                self.analytics?.reportError("adapty_profile_error",
                                            message: error.localizedDescription,
                                            parameters: nil)
                completion?(self.isPro)
            }
        }
    }

    @discardableResult
    public func observeEntitlement(_ handler: @escaping (Bool) -> Void) -> A1ObservationToken {
        let key = UUID()
        let current = withLock { () -> Bool in
            entitlementObservers[key] = handler
            return proFlag
        }

        onMain { handler(current) }

        return A1ObservationToken { [weak self] in
            guard let self else { return }
            self.withLock { self.entitlementObservers[key] = nil }
        }
    }

    /// The one place a vendor profile becomes an entitlement: read, publish, hand back.
    @discardableResult
    private func applyEntitlement(from profile: AdaptyProfile) -> Bool {
        let active = profile.accessLevels[accessLevel]?.isActive ?? false
        withLock { hasResolvedEntitlement = true }
        updateEntitlement(active)
        return active
    }

    /// `true` once Adapty has answered this launch. Until then `isPro` is the cached value from
    /// the previous session, which is the safest assumption for a paying user.
    public var isEntitlementResolved: Bool { withLock { hasResolvedEntitlement } }

    private func updateEntitlement(_ active: Bool) {
        lock.lock()
        guard active != proFlag else { lock.unlock(); return }
        proFlag = active
        UserDefaults.standard.set(active, forKey: Self.entitlementCacheKey)
        let handlers = Array(entitlementObservers.values)
        lock.unlock()

        onMain { handlers.forEach { $0(active) } }
    }

    // MARK: - Paywalls

    public func paywall(for placement: A1Placement,
                        completion: @escaping (Result<A1PaywallConfig, A1PurchaseError>) -> Void) {
        if let cached = cachedPaywall(for: placement) {
            completion(.success(.builder(cached.controller)))
            return
        }

        guard isActivated else {
            reportInactive("paywall(for:)")
            completion(.failure(.paywallUnavailable))
            return
        }

        Adapty.getPaywall(placementId: placement.rawValue, locale: locale) { [weak self] result in
            guard let self else { return }

            switch result {
            case let .success(paywall):
                // The vendor's own discriminator decides which case this placement is:
                // a builder-rendered screen, or a JSON payload the app renders itself.
                guard paywall.hasViewConfiguration else {
                    guard let remote = paywall.remoteConfig else {
                        completion(.failure(.paywallUnavailable))
                        return
                    }
                    completion(.success(.remoteConfig(A1PaywallPayload(placement: placement,
                                                                      locale: remote.locale,
                                                                      jsonString: remote.jsonString))))
                    return
                }
                self.buildController(for: paywall, placement: placement, completion: completion)

            case let .failure(error):
                self.reportLoadFailure(error, placement: placement, completion: completion)
            }
        }
    }

    private func buildController(for paywall: AdaptyPaywall,
                                 placement: A1Placement,
                                 completion: @escaping (Result<A1PaywallConfig, A1PurchaseError>) -> Void) {
        AdaptyUI.getPaywallConfiguration(forPaywall: paywall) { [weak self] result in
            guard let self else { return }

            switch result {
            case let .success(configuration):
                // AdaptyUI.paywallController is @MainActor-isolated, so this must be an
                // async hop rather than the synchronous onMain fast-path.
                DispatchQueue.main.async { [weak self] in
                    guard let self else { return }
                    do {
                        let controller = try AdaptyUI.paywallController(with: configuration, delegate: self)
                        self.cache(controller: controller, paywall: paywall, for: placement)
                        completion(.success(.builder(controller)))
                    } catch {
                        self.analytics?.reportError("adapty_rendering_error",
                                                    message: error.localizedDescription,
                                                    parameters: ["placement": placement.rawValue])
                        completion(.failure(.renderingFailed(error.localizedDescription)))
                    }
                }
            case let .failure(error):
                self.reportLoadFailure(error, placement: placement, completion: completion)
            }
        }
    }

    /// Shared failure arm of both load paths — same event, same non-fatal, same mapped error.
    private func reportLoadFailure(_ error: AdaptyError,
                                   placement: A1Placement,
                                   completion: (Result<A1PaywallConfig, A1PurchaseError>) -> Void) {
        analytics?.log("event_subs_paywall_load_failed")
        analytics?.reportError("adapty_paywall_error",
                               message: error.localizedDescription,
                               parameters: ["placement": placement.rawValue])
        completion(.failure(Self.map(error)))
    }

    public func present(_ placement: A1Placement,
                        from viewController: UIViewController,
                        callbacks: A1PaywallCallbacks) {
        callbacks.onLoading?(true)
        analytics?.log("event_subs_paywall_load_started")

        paywall(for: placement) { [weak self] result in
            guard let self else { return }
            callbacks.onLoading?(false)

            switch result {
            case let .success(.builder(controller)):
                self.store(callbacks, for: controller)
                self.analytics?.log("event_subs_paywall_show_requested")

                if let cached = self.cachedPaywall(for: placement) {
                    Adapty.logShowPaywall(cached.paywall)
                }

                self.onMain {
                    viewController.present(controller, animated: true) {
                        self.analytics?.log(A1Event("event_subs_paywall_screen_shown",
                                                    keys: ["Placement"], values: [placement.rawValue]))
                    }
                }

            case .success(.remoteConfig):
                // No vendor UI for this placement — the app must render it. Surfacing this
                // as an error would be wrong, so the caller is simply told nothing was shown.
                callbacks.onClose?()
                callbacks.onDismiss?()

            case let .failure(error):
                callbacks.onError?(error)
            }
        }
    }

    public func prefetch(_ placements: [A1Placement]) {
        placements.forEach { paywall(for: $0) { _ in } }
    }

    public func restore(completion: @escaping (A1PurchaseResult) -> Void) {
        guard isActivated else {
            reportInactive("restore")
            completion(.failed(.restoreFailed("Subscriptions are not configured")))
            return
        }

        analytics?.log("event_subs_restore_started")

        Adapty.restorePurchases { [weak self] result in
            guard let self else { return }
            switch result {
            case let .success(profile):
                completion(self.applyEntitlement(from: profile)
                    ? .success(A1Transaction(productIdentifier: "", placement: nil, isActive: true))
                    : .failed(.nothingToRestore))
            case let .failure(error):
                self.analytics?.reportError("adapty_restorepurchase_error",
                                            message: error.localizedDescription,
                                            parameters: nil)
                completion(.failed(.restoreFailed(error.localizedDescription)))
            }
        }
    }

    public func setIntegrationIdentifier(key: String, value: String) {
        guard isActivated else {
            reportInactive("setIntegrationIdentifier")
            return
        }

        Adapty.setIntegrationIdentifier(key: key, value: value) { [weak self] error in
            guard let error else { return }
            self?.analytics?.reportError("adapty_integration_identifier_error",
                                         message: error.localizedDescription,
                                         parameters: ["key": key])
        }
    }

    // MARK: - Cache

    private func cachedPaywall(for placement: A1Placement) -> (controller: AdaptyPaywallController, paywall: AdaptyPaywall)? {
        withLock { cachedPaywalls[placement.rawValue] }
    }

    private func cache(controller: AdaptyPaywallController, paywall: AdaptyPaywall, for placement: A1Placement) {
        withLock { cachedPaywalls[placement.rawValue] = (controller, paywall) }
    }

    private func store(_ callbacks: A1PaywallCallbacks, for controller: UIViewController) {
        let key = ObjectIdentifier(controller)
        withLock {
            activeCallbacks[key] = callbacks
            dismissedControllers.remove(key)
        }
    }

    private func callbacks(for controller: UIViewController) -> A1PaywallCallbacks? {
        withLock { activeCallbacks[ObjectIdentifier(controller)] }
    }

    /// Dismiss and fire `onDismiss` exactly once, however the paywall was closed.
    private func finish(_ controller: UIViewController) {
        let key = ObjectIdentifier(controller)
        let (isFirstDismissal, callbacks) = withLock { () -> (Bool, A1PaywallCallbacks?) in
            (dismissedControllers.insert(key).inserted, activeCallbacks[key])
        }
        guard isFirstDismissal else { return }

        onMain {
            controller.dismiss(animated: true) {
                callbacks?.onDismiss?()
                self.withLock { self.activeCallbacks[key] = nil }
            }
        }
    }

    @inline(__always)
    private func withLock<T>(_ work: () -> T) -> T {
        lock.lock(); defer { lock.unlock() }
        return work()
    }

    private func onMain(_ work: @escaping () -> Void) {
        if Thread.isMainThread { work() } else { DispatchQueue.main.async(execute: work) }
    }

    // MARK: - Error mapping

    private static func map(_ error: AdaptyError) -> A1PurchaseError {
        switch error.adaptyErrorCode {
        case .networkFailed:      return .notConnected
        case .paymentCancelled:   return .purchaseFailed("Cancelled")
        default:                  return .unknown(error.localizedDescription)
        }
    }
}

// MARK: - AdaptyPaywallControllerDelegate

extension AdaptyAdapter: AdaptyPaywallControllerDelegate {

    public func paywallController(_ controller: AdaptyPaywallController, didPerform action: AdaptyUI.Action) {
        switch action {
        case .close:
            analytics?.log(A1Event("event_app_paywall_cross_clicked",
                                   keys: ["Placement"], values: [controller.paywallPlacementId]))
            callbacks(for: controller)?.onClose?()
            finish(controller)

        case let .openURL(url):
            UIApplication.shared.open(url, options: [:])

        case .custom:
            break
        }
    }

    public func paywallController(_ controller: AdaptyPaywallController,
                                  didSelectProduct product: AdaptyPaywallProductWithoutDeterminingOffer) {
        analytics?.log(A1Event("event_subs_paywall_plan_selected",
                               keys: ["Placement", "Plan ID"],
                               values: [controller.paywallPlacementId, product.vendorProductId]))
    }

    public func paywallController(_ controller: AdaptyPaywallController,
                                  didStartPurchase product: AdaptyPaywallProduct) {
        analytics?.log("event_subs_purchase_started")
    }

    public func paywallController(_ controller: AdaptyPaywallController,
                                  didFinishPurchase product: AdaptyPaywallProduct,
                                  purchaseResult: AdaptyPurchaseResult) {
        let handlers = callbacks(for: controller)

        switch purchaseResult {
        case .userCancelled:
            analytics?.log("event_subs_purchase_cancelled")
            handlers?.onPurchase?(.cancelled)

        case .pending:
            handlers?.onPurchase?(.pending)
            finish(controller)

        case let .success(profile, _):
            let active = applyEntitlement(from: profile)

            if #available(iOS 15.0, *), let transaction = purchaseResult.sk2Transaction {
                // Routed through the Firebase module so this file never imports Firebase.
                A1SDK.shared.module(FirebaseAnalyticsAdapter.self)?.logTransaction(transaction)
            }

            analytics?.log(A1Event("event_subs_purchase_acknowledged",
                                   keys: ["Placement", "Product"],
                                   values: [controller.paywallPlacementId, product.vendorProductId]))

            handlers?.onPurchase?(.success(A1Transaction(productIdentifier: product.vendorProductId,
                                                         placement: A1Placement(controller.paywallPlacementId),
                                                         isActive: active)))
            finish(controller)
        }
    }

    public func paywallController(_ controller: AdaptyPaywallController,
                                  didFailPurchase product: AdaptyPaywallProduct,
                                  error: AdaptyError) {
        analytics?.log("event_subs_paywall_payment_failed")
        analytics?.reportError("adapty_purchasefailed_error", message: error.localizedDescription, parameters: nil)
        callbacks(for: controller)?.onPurchase?(.failed(Self.map(error)))
    }

    public func paywallControllerDidStartRestore(_ controller: AdaptyPaywallController) {
        analytics?.log("event_subs_restore_started")
    }

    public func paywallController(_ controller: AdaptyPaywallController,
                                  didFinishRestoreWith profile: AdaptyProfile) {
        let active = applyEntitlement(from: profile)

        if active {
            analytics?.log(A1Event("event_app_paywall_restore_acknowledged",
                                   keys: ["Placement"], values: [controller.paywallPlacementId]))
        }

        callbacks(for: controller)?.onRestore?(active
            ? .success(A1Transaction(productIdentifier: "",
                                     placement: A1Placement(controller.paywallPlacementId),
                                     isActive: true))
            : .failed(.nothingToRestore))
    }

    public func paywallController(_ controller: AdaptyPaywallController, didFailRestoreWith error: AdaptyError) {
        analytics?.reportError("adapty_restorepurchase_error", message: error.localizedDescription, parameters: nil)
        callbacks(for: controller)?.onRestore?(.failed(.restoreFailed(error.localizedDescription)))
    }

    public func paywallController(_ controller: AdaptyPaywallController,
                                  didFailLoadingProductsWith error: AdaptyError) -> Bool {
        analytics?.reportError("adapty_productdetailloading_error", message: error.localizedDescription, parameters: nil)
        // true keeps Adapty retrying, matching existing behaviour.
        return true
    }

    public func paywallController(_ controller: AdaptyPaywallController, didFailRenderingWith error: AdaptyUIError) {
        analytics?.reportError("adapty_rendering_error", message: error.localizedDescription, parameters: nil)
        callbacks(for: controller)?.onError?(.renderingFailed(error.localizedDescription))
    }
}
