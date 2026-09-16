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
    /// Placements the app renders itself, kept so `logPaywallShown` can attribute the impression.
    private var nativePaywalls: [String: AdaptyPaywall] = [:]
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
    private var loadTimeout: TimeInterval = 10
    /// Presentations still waiting on the vendor. A timed-out request is removed, so its
    /// late completion is dropped instead of presenting over whatever the user moved on to.
    private var pendingPresentations = Set<UUID>()
    private var integrationIdentityToken: A1ObservationToken?
    private var analytics: AnalyticsProvider?
    private var identityToken: A1ObservationToken?

    /// Firebase Performance trace from `Adapty.activate` to the moment the app has both an
    /// entitlement answer and every prefetched paywall — the wait a user actually feels.
    /// Only recorded when the performance module is registered and enabled. SDK-namespaced.
    public static let readinessTraceName = "a1sdk_adapty_ready"

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
        loadTimeout = context.configuration.paywallLoadTimeout

        Adapty.logLevel = context.configuration.isLoggingEnabled ? .verbose : .error

        // Empty on a first launch — Adapty wants nil rather than "" for an unknown user.
        let userID = context.identity.userID

        // Raised *before* the call, not in its completion: Adapty queues work issued after
        // `activate` returns, and the completion below itself calls back into this adapter.
        isActivated = true

        let placements = context.configuration.prefetchedPlacements
        let readiness = ReadinessTrace(placementCount: placements.count)

        Adapty.activate(apiKey, customerUserId: userID.isEmpty ? nil : userID) { [weak self] error in
            guard let self else { return }
            readiness?.activated(succeeded: error == nil)

            // Runs regardless of activation error, matching existing behaviour: a cached
            // profile may still resolve entitlement while the network is unavailable.
            let proceed = { [weak self] in
                guard let self else { return }
                self.refreshEntitlement { _ in readiness?.profileResolved() }
                for placement in placements {
                    self.paywall(for: placement) { result in
                        if case .failure = result { readiness?.placementLoaded(failed: true) }
                        else { readiness?.placementLoaded(failed: false) }
                    }
                }
            }

            if let error {
                self.analytics?.reportError(.adapty_configuration_error,
                                            message: error.localizedDescription,
                                            parameters: nil)
                proceed()
                return
            }

            self.analytics?.log(.adapty_configuration_successful)
            self.linkIntegrationIdentifiers(identity: context.identity)

            // Builder paywalls need AdaptyUI, whose activation is asynchronous: a prefetch
            // issued before it completes fails with "AdaptyUI not activated" whenever the
            // paywall arrives from the cache first. Wait for it, as the apps always did.
            AdaptyUI.activate { [weak self] uiError in
                if let uiError {
                    self?.analytics?.reportError(.adapty_configuration_error,
                                                 message: uiError.localizedDescription,
                                                 parameters: ["stage": "AdaptyUI"])
                }
                proceed()
            }
        }

        identityToken = context.identity.observe { [weak self] userID in
            guard let self, !userID.isEmpty else { return }
            Adapty.identify(userID) { error in
                guard let error else { return }
                self.analytics?.reportError(.adapty_customer_id_error,
                                            message: error.localizedDescription,
                                            parameters: nil)
            }
        }
    }

    // MARK: - Cross-vendor attribution

    /// Hand the other vendors' ids to Adapty so its revenue integrations can stitch users.
    /// Each source is optional: an app that did not register a module simply skips that link.
    private func linkIntegrationIdentifiers(identity: A1Identity) {
        if let id = A1SDK.shared.module(FirebaseAnalyticsAdapter.self)?.appInstanceID, !id.isEmpty {
            setIntegrationIdentifier(key: "firebase_app_instance_id", value: id)
        }
        if let id = A1SDK.shared.module(AppMetricaAdapter.self)?.deviceID, !id.isEmpty {
            setIntegrationIdentifier(key: "appmetrica_device_id", value: id)
        }
        // The AppMetrica profile id is the app's user id (that is what userProfileID is set to),
        // so it follows identity — including the first-launch resolution. Only when AppMetrica
        // is registered: without it the key would carry an id no AppMetrica profile has.
        if A1SDK.shared.module(AppMetricaAdapter.self) != nil {
            integrationIdentityToken = identity.observe { [weak self] userID in
                guard !userID.isEmpty else { return }
                self?.setIntegrationIdentifier(key: "appmetrica_profile_id", value: userID)
            }
        }
        // Meta's id only exists once its SDK has seen didFinishLaunching.
        A1SDK.shared.module(MetaAdapter.self)?.whenInitialized { [weak self] anonymousID in
            guard !anonymousID.isEmpty else { return }
            self?.setIntegrationIdentifier(key: "facebook_anonymous_id", value: anonymousID)
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
        analytics?.reportError(.adapty_not_activated,
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
                self.analytics?.reportError(.adapty_profile_error,
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
                    self.withLock { self.nativePaywalls[placement.rawValue] = paywall }
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
                        self.analytics?.reportError(.adapty_rendering_error,
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
        analytics?.log(.event_subs_paywall_load_failed)
        analytics?.reportError(.adapty_paywall_error,
                               message: error.localizedDescription,
                               parameters: ["placement": placement.rawValue])
        completion(.failure(Self.map(error)))
    }

    public func present(_ placement: A1Placement,
                        from viewController: UIViewController,
                        callbacks: A1PaywallCallbacks) {
        callbacks.onLoading?(true)
        analytics?.log(.event_subs_paywall_load_started)

        // Matches the pre-migration 10s timer: hide the loader and forget the request. No
        // error is raised — the user has already moved on, and a late paywall over a
        // different screen is worse than none.
        let request = UUID()
        withLock { _ = pendingPresentations.insert(request) }
        let timeout = DispatchWorkItem { [weak self] in
            guard let self, self.withLock({ self.pendingPresentations.remove(request) != nil }) else { return }
            callbacks.onLoading?(false)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + loadTimeout, execute: timeout)

        paywall(for: placement) { [weak self] result in
            guard let self else { return }
            // Timed out already: the loader is gone and the user has moved on — drop it.
            guard self.withLock({ self.pendingPresentations.remove(request) != nil }) else { return }
            timeout.cancel()
            callbacks.onLoading?(false)

            switch result {
            case let .success(.builder(controller)):
                self.onMain {
                    // Already on screen — a double tap, or a second screen asking for the same
                    // cached placement. The apps have always ignored that silently, and UIKit
                    // would refuse the present anyway; re-storing callbacks would only lose the
                    // first caller's.
                    if controller.presentingViewController != nil || controller.parent != nil { return }
                    // The presenter left the hierarchy while the paywall loaded: nothing to
                    // present on. "No window" alone is not enough — a screen presenting from
                    // viewWillAppear has no window yet but is about to; detached means no
                    // window, no parent container and no presenter.
                    let detached = viewController.viewIfLoaded?.window == nil
                        && viewController.parent == nil
                        && viewController.presentingViewController == nil
                    guard !detached else {
                        callbacks.onError?(.paywallUnavailable)
                        return
                    }

                    self.store(callbacks, for: controller)
                    self.analytics?.log(.event_subs_paywall_show_requested)

                    // No manual impression log here: the Builder controller logs its own on
                    // appear, so a second call counted every view twice. Natively rendered
                    // placements log through `logPaywallShown`.
                    // Deferred one turn: a cached paywall requested from viewWillAppear would
                    // otherwise present inside the presenter's own appearance transition.
                    DispatchQueue.main.async {
                        viewController.present(controller, animated: true) {
                            self.analytics?.log(A1Event(.event_subs_paywall_screen_shown,
                                                        keys: ["Placement"], values: [placement.rawValue]))
                        }
                    }
                }

            case let .success(.remoteConfig(payload)):
                // No vendor UI for this placement — the app renders it from the payload.
                // Without a renderer the request cannot be honoured; reporting it as a
                // close would tell the app the user dismissed a paywall that never appeared.
                self.onMain {
                    if let render = callbacks.onRemoteConfig {
                        render(payload)
                    } else {
                        callbacks.onError?(.paywallUnavailable)
                    }
                }

            case let .failure(error):
                callbacks.onError?(error)
            }
        }
    }

    public func prefetch(_ placements: [A1Placement]) {
        placements.forEach { paywall(for: $0) { _ in } }
    }

    public func logPaywallShown(_ placement: A1Placement) {
        if let paywall = withLock({ nativePaywalls[placement.rawValue] }) {
            Adapty.logShowPaywall(paywall)
            return
        }
        guard isActivated else {
            reportInactive("logPaywallShown")
            return
        }
        // Not resolved through this adapter yet (the app fetched nothing before rendering):
        // fetch once so the impression is still attributed to the right paywall variation.
        Adapty.getPaywall(placementId: placement.rawValue, locale: locale) { [weak self] result in
            // A Builder placement logs its own impression; logging it here would double count.
            guard case let .success(paywall) = result, !paywall.hasViewConfiguration else { return }
            self?.withLock { self?.nativePaywalls[placement.rawValue] = paywall }
            Adapty.logShowPaywall(paywall)
        }
    }

    public func restore(completion: @escaping (A1PurchaseResult) -> Void) {
        guard isActivated else {
            reportInactive("restore")
            completion(.failed(.restoreFailed("Subscriptions are not configured")))
            return
        }

        analytics?.log(.event_subs_restore_started)

        Adapty.restorePurchases { [weak self] result in
            guard let self else { return }
            switch result {
            case let .success(profile):
                completion(self.applyEntitlement(from: profile)
                    ? .success(A1Transaction(productIdentifier: "", placement: nil, isActive: true))
                    : .failed(.nothingToRestore))
            case let .failure(error):
                self.analytics?.reportError(.adapty_restorepurchase_error,
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
            self?.analytics?.reportError(.adapty_integration_identifier_error,
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
            let done = {
                // Per presentation, not per controller: cached controllers are shown again,
                // and the next close must be able to finish them again. Cleared before the
                // callback, so an app that re-presents the same placement from onDismiss
                // keeps the callbacks it just stored.
                self.withLock {
                    self.activeCallbacks[key] = nil
                    self.dismissedControllers.remove(key)
                }
                callbacks?.onDismiss?()
            }
            if let navigation = controller.navigationController,
               let index = navigation.viewControllers.firstIndex(of: controller), index > 0 {
                // Pushed rather than presented (an app that shows `paywall(for:)` itself).
                // Pop to the screen beneath the paywall, not whatever happens to be on top.
                // Checked before `presentingViewController`, which a controller pushed inside
                // a presented navigation stack inherits from its container.
                CATransaction.begin()
                CATransaction.setCompletionBlock(done)
                navigation.popToViewController(navigation.viewControllers[index - 1], animated: true)
                CATransaction.commit()
            } else if controller.presentingViewController != nil {
                controller.dismiss(animated: true, completion: done)
            } else {
                // The app already took it off screen. UIKit would never run a dismiss
                // completion for a controller that is not presented, so finish here.
                done()
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
            analytics?.log(A1Event(.event_app_paywall_cross_clicked,
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
        analytics?.log(A1Event(.event_subs_paywall_plan_selected,
                               keys: ["Placement", "Plan ID"],
                               values: [controller.paywallPlacementId, product.vendorProductId]))
    }

    public func paywallController(_ controller: AdaptyPaywallController,
                                  didStartPurchase product: AdaptyPaywallProduct) {
        analytics?.log(.event_subs_purchase_started)
    }

    public func paywallController(_ controller: AdaptyPaywallController,
                                  didFinishPurchase product: AdaptyPaywallProduct,
                                  purchaseResult: AdaptyPurchaseResult) {
        let handlers = callbacks(for: controller)

        switch purchaseResult {
        case .userCancelled:
            analytics?.log(.event_subs_purchase_cancelled)
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

            analytics?.log(A1Event(.event_subs_purchase_acknowledged,
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
        analytics?.log(.event_subs_paywall_payment_failed)
        analytics?.reportError(.adapty_purchasefailed_error, message: error.localizedDescription, parameters: nil)
        callbacks(for: controller)?.onPurchase?(.failed(Self.map(error)))
    }

    public func paywallControllerDidStartRestore(_ controller: AdaptyPaywallController) {
        analytics?.log(.event_subs_restore_started)
    }

    public func paywallController(_ controller: AdaptyPaywallController,
                                  didFinishRestoreWith profile: AdaptyProfile) {
        let active = applyEntitlement(from: profile)

        if active {
            analytics?.log(A1Event(.event_app_paywall_restore_acknowledged,
                                   keys: ["Placement"], values: [controller.paywallPlacementId]))
        }

        callbacks(for: controller)?.onRestore?(active
            ? .success(A1Transaction(productIdentifier: "",
                                     placement: A1Placement(controller.paywallPlacementId),
                                     isActive: true))
            : .failed(.nothingToRestore))
    }

    public func paywallController(_ controller: AdaptyPaywallController, didFailRestoreWith error: AdaptyError) {
        analytics?.reportError(.adapty_restorepurchase_error, message: error.localizedDescription, parameters: nil)
        callbacks(for: controller)?.onRestore?(.failed(.restoreFailed(error.localizedDescription)))
    }

    public func paywallController(_ controller: AdaptyPaywallController,
                                  didFailLoadingProductsWith error: AdaptyError) -> Bool {
        analytics?.reportError(.adapty_productdetailloading_error, message: error.localizedDescription, parameters: nil)
        // true keeps Adapty retrying, matching existing behaviour.
        return true
    }

    public func paywallController(_ controller: AdaptyPaywallController, didFailRenderingWith error: AdaptyUIError) {
        analytics?.reportError(.adapty_rendering_error, message: error.localizedDescription, parameters: nil)
        callbacks(for: controller)?.onError?(.renderingFailed(error.localizedDescription))
    }
}

// MARK: - Readiness trace

/// Milestones on `AdaptyAdapter.readinessTraceName`, all measured from `Adapty.activate`:
/// `activate_ms` (vendor answered), `profile_ms` (entitlement known), `prefetch_ms` (last
/// prefetched paywall arrived) and a `prefetch_failed` count; the trace's own duration is the
/// total. The `activation` attribute (`ok`/`failed`) lets the console segment the two cases.
/// Nil when performance collection is off, so every call site is a no-op on an optional.
private final class ReadinessTrace {

    private let performance: PerformanceAdapter
    private let trace: A1TraceHandle
    private let started = CFAbsoluteTimeGetCurrent()
    private let lock = NSLock()
    private var profilePending = true
    private var placementsPending: Int

    init?(placementCount: Int) {
        guard let performance = A1SDK.shared.module(PerformanceAdapter.self),
              let trace = performance.startTrace(AdaptyAdapter.readinessTraceName) else { return nil }
        self.performance = performance
        self.trace = trace
        placementsPending = placementCount
    }

    func activated(succeeded: Bool) {
        trace.setValue(elapsed, forCounter: "activate_ms")
        trace.setValue(succeeded ? "ok" : "failed", forAttribute: "activation")
    }

    func profileResolved() {
        trace.setValue(elapsed, forCounter: "profile_ms")
        finishIfReady { profilePending = false }
    }

    func placementLoaded(failed: Bool) {
        if failed { trace.increment("prefetch_failed") }
        finishIfReady {
            placementsPending -= 1
            if placementsPending == 0 { trace.setValue(elapsed, forCounter: "prefetch_ms") }
        }
    }

    private var elapsed: Int64 { Int64((CFAbsoluteTimeGetCurrent() - started) * 1000) }

    /// Stops the trace once the profile and every placement have reported. `stop` is
    /// idempotent, so the ordering of the two kinds of completion does not matter.
    private func finishIfReady(_ update: () -> Void) {
        lock.lock()
        update()
        let done = !profilePending && placementsPending <= 0
        lock.unlock()
        if done { performance.stop(trace) }
    }
}
