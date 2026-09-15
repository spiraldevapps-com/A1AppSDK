//
//  AdMobAdapter.swift
//  A1AppSDK
//
//  AdMob behind `AdsProvider`.
//
//  Deliberately delegates to the existing `AdsHandler`/`Ads` pair rather than
//  reimplementing them: the frequency-cap logic in `AdsHandler` is tuned revenue
//  behaviour, and rewriting it during a structural refactor is how you lose money
//  quietly. This adapter changes the shape of the API, not what it decides.
//

import Foundation
import UIKit

/// Banner handle that keeps the vendor's view type out of the caller's hands.
private final class AdMobBannerHandle: A1BannerAd {
    let containerView: UIView
    private let banner: AdsBannerType

    init(banner: AdsBannerType, view: UIView) {
        self.banner = banner
        self.containerView = view
    }

    func show() { banner.show() }
    func remove() { banner.remove() }
    func updateLayout() { banner.updateLayout() }
}

public final class AdMobAdapter: A1Module, AdsProvider {

    public var phase: A1BootPhase { .advertising }

    /// Resolved in `configure(context:)`, never at construction.
    ///
    /// `AdsHandler.shared` holds `Ads.shared`, whose `init` calls
    /// `GADMobileAds.sharedInstance()`. Touching it from a stored-property initialiser
    /// would create Mobile Ads state the moment this adapter is *constructed* — which
    /// `A1SDK.standardModules()` does in one array literal, before any module has been
    /// configured and before consent has even been requested.
    private var handler: AdsHandler?
    private var isBooted = false
    private var lastConfiguration: AdsConfiguration?
    private var isPro = false
    /// A `setDisabled(_:)` that arrived before boot, replayed once the handler exists.
    private var pendingDisabled: Bool?
    private var entitlementToken: A1ObservationToken?
    private var analytics: AnalyticsProvider?

    public init() {}

    // MARK: - A1Module

    public func configure(context: A1ModuleContext) {
        analytics = context.analytics
        isBooted = true

        if let pending = pendingDisabled {
            pendingDisabled = nil
            Ads.shared.setDisabled(pending)
        }

        // A host that supplied a configuration before `A1SDK.configure(with:)` ran had it
        // held rather than applied; apply it now, through the same consent gate.
        if lastConfiguration != nil { applyConfiguration() }

        // Monetization boots at an earlier phase, so the subscription provider already
        // exists here. This replaces the hand-written setPro()/removePro() plumbing each
        // app used to carry: entitlement changes now reconfigure ads on their own.
        entitlementToken = A1SDK.shared.subscriptions?.observeEntitlement { [weak self] isPro in
            self?.applyEntitlement(isPro)
        }
    }

    /// The one place `AdsHandler.shared` — and therefore the Mobile Ads singleton — is reached.
    private var resolvedHandler: AdsHandler? {
        guard isBooted else { return nil }
        if let handler { return handler }
        let resolved = AdsHandler.shared
        handler = resolved
        return resolved
    }

    private func applyEntitlement(_ isPro: Bool) {
        self.isPro = isPro
        // Nothing to re-apply until the app has supplied a remote config.
        guard let configuration = lastConfiguration, let handler = resolvedHandler else { return }
        handler.configureAds(config: configuration, pro: isPro)
    }

    // MARK: - AdsProvider

    public func configure(_ configuration: AdsConfiguration, isPro: Bool) {
        lastConfiguration = configuration
        self.isPro = isPro

        // Before boot there is nothing to configure against: hold the values and let
        // `configure(context:)` apply them once the module has actually started.
        guard isBooted else { return }
        applyConfiguration()
    }

    private func applyConfiguration() {
        guard let configuration = lastConfiguration, let handler = resolvedHandler else { return }

        // Never start the Mobile Ads SDK before consent has been resolved: it begins
        // preloading as soon as it starts, which is exactly what UMP exists to prevent.
        guard let consent = A1SDK.shared.module(ConsentAdapter.self) else {
            handler.configureAds(config: configuration, pro: isPro)
            return
        }
        consent.whenResolved { [weak self] in
            guard let self,
                  let config = self.lastConfiguration,
                  let handler = self.resolvedHandler else { return }
            handler.configureAds(config: config, pro: self.isPro)
        }
    }

    public func state(for format: A1AdFormat) -> A1AdState {
        // Before boot nothing is loaded and nothing is showing — the honest answer, and
        // one that does not create Mobile Ads state to produce it.
        guard let handler = resolvedHandler else { return .idle(format) }

        switch format {
        case .appOpen:
            return A1AdState(format: format,
                             isReady: handler.appOpenAdAvailable(),
                             isShowing: handler.appOpenAdShowing(),
                             isLoading: handler.appOpenAdLoading())
        case .interstitial:
            return A1AdState(format: format,
                             isReady: handler.interAdAvailable(),
                             isShowing: handler.interAdShowing())
        case .rewarded:
            return A1AdState(format: format,
                             isReady: handler.rewardedAdAvailable(),
                             isShowing: handler.rewardedAdShowing())
        case .rewardedInterstitial:
            return A1AdState(format: format,
                             isReady: handler.rewardedInterAdAvailable(),
                             isShowing: handler.rewardedInterAdShowing())
        case .banner, .native:
            // Neither format exposes readiness through the handler; they are built on demand.
            return A1AdState(format: format, isReady: handler.canShowAds(), isShowing: false)
        }
    }

    /// - Important: for `.interstitial` this is **stateful**. `AdsHandler.canShowInterAd()`
    ///   increments the click counter that drives `interClickInterval`, so it must be called
    ///   exactly once per show opportunity. Calling it twice to "check then check again"
    ///   changes ad pacing. `canShow(_:)` from the protocol extension calls this once.
    ///
    /// Safe and cheap before boot: host view controllers call this constantly, so the
    /// pre-boot answer is `.adsDisabled` — the same refusal the handler gives with its
    /// default configuration, reached without touching the vendor.
    public func suppressionReason(for format: A1AdFormat) -> A1AdSuppressionReason? {
        guard let handler = resolvedHandler else { return .adsDisabled }

        let allowed: Bool
        switch format {
        case .interstitial:         allowed = handler.canShowInterAd()
        case .appOpen:              allowed = handler.canShowAppOpenAd()
        case .banner:               allowed = handler.canShowBannerAd()
        case .rewarded,
             .rewardedInterstitial: allowed = handler.canShowRewardedAd()
        case .native:               allowed = handler.canShowAds()
        }

        return allowed ? nil : diagnosticReason(for: format, handler: handler)
    }

    /// Best-effort explanation for a refusal. Pure reads — safe to call after the decision
    /// has already been made, and never consulted to make one.
    private func diagnosticReason(for format: A1AdFormat, handler: AdsHandler) -> A1AdSuppressionReason {
        if isPro { return .userIsPro }
        guard let config = lastConfiguration else { return .adsDisabled }
        if !config.adsEnabled { return .adsDisabled }
        if !isReachable { return .notConnected }

        let enabled: Bool
        switch format {
        case .interstitial:         enabled = config.interEnabled
        case .appOpen:              enabled = config.appOpenEnabled
        case .banner:               enabled = config.bannerEnabled
        case .rewarded,
             .rewardedInterstitial: enabled = config.rewardedEnabled
        case .native:               enabled = config.nativeEnabled
        }
        if !enabled { return .formatDisabled }

        if handler.interAdShowing() || handler.appOpenAdShowing() { return .anotherAdShowing }
        if !state(for: format).isReady { return .notLoaded }
        return .withinInterval
    }

    public func show(_ format: A1AdFormat,
                     from viewController: UIViewController,
                     callbacks: A1AdCallbacks) {
        // No ad can exist before boot, and asking for one would start the vendor early.
        guard isBooted else {
            callbacks.onNotReady?()
            return
        }

        switch format {
        case .appOpen:
            Ads.shared.showAppOpenAd(from: viewController,
                                     onOpen: callbacks.onOpen,
                                     onClose: callbacks.onClose,
                                     onError: callbacks.onError)

        case .interstitial:
            Ads.shared.showInterstitialAd(from: viewController,
                                          onOpen: callbacks.onOpen,
                                          onClose: callbacks.onClose,
                                          onError: callbacks.onError)

        case .rewarded:
            Ads.shared.showRewardedAd(from: viewController,
                                      onOpen: callbacks.onOpen,
                                      onClose: callbacks.onClose,
                                      onError: callbacks.onError,
                                      onNotReady: callbacks.onNotReady,
                                      onReward: { callbacks.onReward?($0) })

        case .rewardedInterstitial:
            Ads.shared.showRewardedInterstitialAd(from: viewController,
                                                  onOpen: callbacks.onOpen,
                                                  onClose: callbacks.onClose,
                                                  onError: callbacks.onError,
                                                  onReward: { callbacks.onReward?($0) })

        case .banner, .native:
            // Not presentable full-screen; banners come from makeBanner(in:callbacks:).
            callbacks.onNotReady?()
        }
    }

    public func makeBanner(in viewController: UIViewController,
                           callbacks: A1AdCallbacks) -> A1BannerAd? {
        guard isBooted else { return nil }

        guard let (banner, view) = Ads.shared.makeBannerAd(in: viewController,
                                                           onOpen: callbacks.onOpen,
                                                           onClose: callbacks.onClose,
                                                           onError: callbacks.onError,
                                                           onWillPresentScreen: nil,
                                                           onWillDismissScreen: nil,
                                                           onDidDismissScreen: nil)
        else { return nil }

        return AdMobBannerHandle(banner: banner, view: view)
    }

    public func setDisabled(_ isDisabled: Bool) {
        // Held rather than dropped: a host that disables ads before boot must not find
        // them switched on afterwards.
        guard isBooted else {
            pendingDisabled = isDisabled
            return
        }
        Ads.shared.setDisabled(isDisabled)
    }

    /// Load rewarded ads, which are configured separately from the main ad set.
    public func prepareRewarded() {
        resolvedHandler?.configureRewardedAd()
    }
}
