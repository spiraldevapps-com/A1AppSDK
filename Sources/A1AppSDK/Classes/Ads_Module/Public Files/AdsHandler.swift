//
//  AdsHandler.swift
//  A1Apps
//
//  Created by Navnidhi Sharma on 24/01/24.
//  Copyright © 2024 A1Apps. All rights reserved.
//

import UIKit
import GoogleMobileAds

/// Backed by `ReachabilityAdapter`'s single NWPathMonitor. Defaults to `true` when the module
/// is not registered, so an app that never adopts it is not silently starved of ads.
public var isReachable: Bool {
    A1SDK.shared.module(ReachabilityAdapter.self)?.isConnected ?? true
}

public class AdsHandler {
    public var a1Ads = Ads.shared
    public static var shared = AdsHandler()
    private let notificationCenterAds: NotificationCenter = .default
    private var isPro = false
    private var adConfig = AdsConfiguration()
    public var interTriedCount = 0
    public var interLoadTime: Date?
    public var appOpenLoadTime: Date?
    
    public func configureAds(config: AdsConfiguration = AdsConfiguration(), pro: Bool) {
        guard !pro, config.adsEnabled else {
            adConfig = config
            isPro = pro
            Ads.shared.setDisabled(true)
            return
        }

        // With a complete set of core unit ids we only rebuild the AdMob objects when something
        // that actually feeds them changed; otherwise a repeat call just refreshes the cached
        // config. An incomplete set always rebuilds, exactly as before.
        let hasCoreUnitIds = !config.appOpenID.isEmpty && !config.interID.isEmpty && !config.bannerID.isEmpty
        let needsReconfigure = !hasCoreUnitIds || a1Ads.getConfiguration.map { current in
            config.adsEnabled != current.adsEnabled
                || config.appOpenID != current.appOpenID
                || config.interID != current.interID
                || config.bannerID != current.bannerID
                || config.rewardedID != current.rewardedID
                || pro != isPro
        } ?? true

        isPro = pro
        adConfig = config
        if needsReconfigure { configureA1Ads() }
        Ads.shared.setDisabled(false)
    }
    
    public func appOpenAdSplashShowing() -> Bool {
        return a1Ads.isAppOpenAdSplashShowing
    }

    public func setAppOpenAdSplashShowing(_ value: Bool) {
        a1Ads.isAppOpenAdSplashShowing = value
    }

    public func appOpenAdAvailable() -> Bool {
        return a1Ads.isAppOpenAdReady
    }
    
    public func appOpenAdShowing() -> Bool {
        return a1Ads.isAppOpenAdShowing
    }
    
    public func appOpenAdLoading() -> Bool {
        return a1Ads.isAppOpenAdLoading
    }
    
    public func interAdAvailable() -> Bool {
        return a1Ads.isInterstitialAdReady
    }

    public func interAdShowing() -> Bool {
        return a1Ads.isInterAdShowing
    }
    
    public func rewardedAdAvailable() -> Bool {
        return a1Ads.isRewardedAdReady
    }

    public func rewardedAdShowing() -> Bool {
        return a1Ads.isRewardedAdShowing
    }

    public func rewardedInterAdAvailable() -> Bool {
        return a1Ads.isRewardedInterstitialAdReady
    }

    public func rewardedInterAdShowing() -> Bool {
        return a1Ads.isRewardedInterstitialAdShowing
    }

    public func canShowBannerAd() -> Bool {
        return isReachable && !isPro && adConfig.adsEnabled && adConfig.bannerEnabled
    }
    
    public func canShowRewardedAd() -> Bool {
        return isReachable && !isPro && adConfig.adsEnabled && adConfig.rewardedEnabled
    }

    public func canShowInterAd() -> Bool {
        // Incremented before every guard on purpose: pro and offline users still advance the
        // click-interval pacing. Do not move this below the guard.
        interTriedCount += 1
        guard canShowFullScreenAd, adConfig.interEnabled else { return false }

        let now = Date()
        if isBlockedByOtherFormat(appOpenLoadTime, now: now) { return false }
        guard let loadTime = interLoadTime else { return true }
        if now.timeIntervalSince(loadTime) < TimeInterval(adConfig.interInterval)
            || interTriedCount < adConfig.interClickInterval + 1 {
            return false
        }
        interTriedCount = 0
        return true
    }

    public func canShowAds() -> Bool {
        return (!isPro && adConfig.adsEnabled)
    }

    public func canShowAppOpenAd() -> Bool {
        guard canShowFullScreenAd, adConfig.appOpenEnabled else { return false }

        let now = Date()
        if isBlockedByOtherFormat(interLoadTime, now: now) { return false }
        guard let loadTime = appOpenLoadTime else { return true }
        return now.timeIntervalSince(loadTime) > TimeInterval(adConfig.appOpenInterval)
    }

    /// Shared gate for the two full-screen formats. Term order matches the original
    /// short-circuit: the cheap "already showing" reads run before the reachability lookup.
    private var canShowFullScreenAd: Bool {
        !a1Ads.isInterAdShowing && !a1Ads.isAppOpenAdShowing && isReachable && !isPro && adConfig.adsEnabled
    }

    /// Cross-format cooldown: an app-open ad blocks an interstitial (and vice versa) for
    /// `appOpenInterInterval` seconds after the other format last loaded.
    private func isBlockedByOtherFormat(_ otherLoadTime: Date?, now: Date) -> Bool {
        guard let otherLoadTime = otherLoadTime else { return false }
        return now.timeIntervalSince(otherLoadTime) < TimeInterval(adConfig.appOpenInterInterval)
    }

    private func configureA1Ads() {
        Ads.shared.configure(from: adConfig,
                             requestBuilder: AdsRequestBuilder())

        // Ads are now ready to be displayed
        notificationCenterAds.post(name: .adsConfigureCompletion, object: nil)
    }

    public func configureRewardedAd() {
        Ads.shared.configureRewardedAds()
    }
    
}
private final class AdsRequestBuilder: AdsRequestBuilderType {
    func build() -> GADRequest {
        GADRequest()
    }
}
extension Notification.Name {
    static let adsConfigureCompletion = Notification.Name("AdsConfigureCompletion")
}
