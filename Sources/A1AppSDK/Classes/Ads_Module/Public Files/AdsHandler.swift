//
//  AdsHandler.swift
//  A1Apps
//
//  Created by Navnidhi Sharma on 24/01/24.
//  Copyright © 2024 A1Apps. All rights reserved.
//

import UIKit
import GoogleMobileAds

public var isReachable: Bool {
   return NetworkReachability.isConnectedToNetwork()
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
        if pro || !config.adsEnabled {
            adConfig = config
            isPro = pro
            Ads.shared.setDisabled(true)
        } else if config.appOpenID != "", config.interID != "", config.bannerID != "" {
            if let configuration = a1Ads.getConfiguration {
                if config.adsEnabled != configuration.adsEnabled || config.appOpenID != configuration.appOpenID || config.interID != configuration.interID || config.bannerID != configuration.bannerID || config.rewardedID != configuration.rewardedID || pro != isPro {
                    isPro = pro
                    adConfig = config
                    configureA1Ads()
                } else {
                    isPro = pro
                    adConfig = config
                }
            } else {
                isPro = pro
                adConfig = config
                configureA1Ads()
            }
            Ads.shared.setDisabled(false)
        } else {
            adConfig = config
            isPro = pro
            configureA1Ads()
            Ads.shared.setDisabled(false)
        }
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
        interTriedCount += 1
        guard !a1Ads.isInterAdShowing && !a1Ads.isAppOpenAdShowing && isReachable && !isPro && adConfig.adsEnabled && adConfig.interEnabled else { return false }
        print("Inter interval is \(adConfig.interInterval) count is \(interTriedCount)")
        // Check if ad was loaded more than n hours ago.
        if let openLoadTime = appOpenLoadTime {
            print("Inter - App open diff \(Date().timeIntervalSince(openLoadTime))")
            if Date().timeIntervalSince(openLoadTime) < TimeInterval(adConfig.appOpenInterInterval) {
                return false
            }
        }
        if let loadTime = interLoadTime {
            print("Inter diff \(Date().timeIntervalSince(loadTime))")
            if Date().timeIntervalSince(loadTime) < TimeInterval(adConfig.interInterval) || interTriedCount < adConfig.interClickInterval + 1 {
                return false
            } else {
                interTriedCount = 0
            }
        }
        return true
    }
    
    public func canShowAds() -> Bool {
        return (!isPro && adConfig.adsEnabled)
    }
    
    public func canShowAppOpenAd() -> Bool {
        guard !a1Ads.isInterAdShowing && !a1Ads.isAppOpenAdShowing && isReachable && !isPro && adConfig.adsEnabled && adConfig.appOpenEnabled else { return false }
        print("App open interval is \(TimeInterval(adConfig.appOpenInterval))")
        // Check if ad was loaded more than n hours ago.
        if let interTime = interLoadTime {
            print("inter - App open diff \(Date().timeIntervalSince(interTime))")
            if Date().timeIntervalSince(interTime) < TimeInterval(adConfig.appOpenInterInterval) {
                return false
            }
        }
        if let loadTime = appOpenLoadTime {
            print("App open diff \(Date().timeIntervalSince(loadTime))")
            return Date().timeIntervalSince(loadTime) > TimeInterval(adConfig.appOpenInterval)
        }
        return true
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
