//
//  AdsRewarded.swift
//  A1IOSLib
//
//  Created by Mohammad Zaid on 28/11/23.
//

import Foundation
import GoogleMobileAds

protocol AdsRewardedType: AnyObject {
    var isReady: Bool { get }
    var isShowing: Bool { get }
    func load()
    func show(from viewController: UIViewController,
              onOpen: (() -> Void)?,
              onClose: (() -> Void)?,
              onError: ((Error) -> Void)?,
              onNotReady: (() -> Void)?,
              onReward: @escaping (NSDecimalNumber) -> Void)
}

final class AdsRewarded: NSObject {

    // MARK: - Properties

    private let adUnitId: String
    private let request: () -> Request
    
    private var onOpen: (() -> Void)?
    private var onClose: (() -> Void)?
    private var onError: ((Error) -> Void)?
    
    private var isShowingRewardedAd = false
    private var rewardedAd: RewardedAd?

    // MARK: - Initialization
    
    init(adUnitId: String, request: @escaping () -> Request) {
        self.adUnitId = adUnitId
        self.request = request
    }
}

// MARK: - AdsRewardedType

extension AdsRewarded: AdsRewardedType {
    var isReady: Bool {
        rewardedAd != nil
    }
    
    var isShowing: Bool {
        isShowingRewardedAd
    }
    
    func load() {
        EventManager.shared.logEvent(title: AdsKey.event_ad_rewarded_load_start.rawValue)
        RewardedAd.load(with: adUnitId, request: request()) { [weak self] (ad, error) in
            guard let self = self else { return }

            if let error = error {
                EventManager.shared.logEvent(title: AdsKey.event_ad_rewarded_load_failed.rawValue)
                self.onError?(error)
                return
            }
            
            EventManager.shared.logEvent(title: AdsKey.event_ad_rewarded_loaded.rawValue)
            self.rewardedAd = ad
            self.rewardedAd?.fullScreenContentDelegate = self
            
        }
    }
 
    func show(from viewController: UIViewController,
              onOpen: (() -> Void)?,
              onClose: (() -> Void)?,
              onError: ((Error) -> Void)?,
              onNotReady: (() -> Void)?,
              onReward: @escaping (NSDecimalNumber) -> Void) {
        self.onOpen = onOpen
        self.onClose = onClose
        self.onError = onError
        EventManager.shared.logEvent(title: AdsKey.event_ad_rewarded_show_requested.rawValue)
        guard let rewardedAd = rewardedAd else {
            load()
            EventManager.shared.logEvent(title: AdsKey.event_ad_rewarded_show_failed.rawValue)
            onError?(AdsError.rewardedAdNotLoaded)
            onNotReady?()
            return
        }

        do {
            try rewardedAd.canPresent(from: viewController)
            EventManager.shared.logEvent(title: AdsKey.event_ad_rewarded_shown.rawValue)
            let rewardAmount = rewardedAd.adReward.amount
            rewardedAd.present(from: viewController, userDidEarnRewardHandler: {
                onReward(rewardAmount)
            })
        } catch {
            load()
            EventManager.shared.logEvent(title: AdsKey.event_ad_rewarded_show_failed.rawValue)
            onError?(error)
            onNotReady?()
            return
        }
    }
}

// MARK: - FullScreenContentDelegate

extension AdsRewarded: FullScreenContentDelegate {
    func adDidRecordImpression(_ ad: FullScreenPresentingAd) {
        print("AdsRewarded did record impression for ad: \(ad)")
    }

    func adWillPresentFullScreenContent(_ ad: FullScreenPresentingAd) {
        isShowingRewardedAd = true
        onOpen?()
    }

    func adDidDismissFullScreenContent(_ ad: FullScreenPresentingAd) {
        // Nil out reference
        isShowingRewardedAd = false
        rewardedAd = nil
        // Send callback
        onClose?()
        // Load the next ad so its ready for displaying
        load()
    }

    func ad(_ ad: FullScreenPresentingAd, didFailToPresentFullScreenContentWithError error: Error) {
        EventManager.shared.logEvent(title: AdsKey.event_ad_rewarded_show_failed.rawValue)
        onError?(error)
    }
}
