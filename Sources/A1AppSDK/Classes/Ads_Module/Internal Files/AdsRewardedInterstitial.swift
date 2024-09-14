//
//  AdsRewardedInterstitial.swift
//  A1IOSLib
//
//  Created by Mohammad Zaid on 28/11/23.
//

import GoogleMobileAds

protocol AdsRewardedInterstitialType: AnyObject {
    var isReady: Bool { get }
    var isShowing: Bool { get }
    func load()
    func stopLoading()
    func show(from viewController: UIViewController,
              onOpen: (() -> Void)?,
              onClose: (() -> Void)?,
              onError: ((Error) -> Void)?,
              onReward: @escaping (NSDecimalNumber) -> Void)
}

final class AdsRewardedInterstitial: NSObject {

    // MARK: - Properties

    private let adUnitId: String
    private let request: () -> GADRequest
    
    private var onOpen: (() -> Void)?
    private var onClose: (() -> Void)?
    private var onError: ((Error) -> Void)?

    private var rewardedInterstitialAd: GADRewardedInterstitialAd?
    private var isShowingRewardedInterstitialAd = false

    // MARK: - Initialization

    init(adUnitId: String, request: @escaping () -> GADRequest) {
        self.adUnitId = adUnitId
        self.request = request
    }
}

// MARK: - AdsRewardedInterstitialType

extension AdsRewardedInterstitial: AdsRewardedInterstitialType {
    var isReady: Bool {
        rewardedInterstitialAd != nil
    }
    
    var isShowing: Bool {
        isShowingRewardedInterstitialAd
    }

    func load() {
        GADRewardedInterstitialAd.load(withAdUnitID: adUnitId, request: request()) { [weak self] (ad, error) in
            guard let self = self else { return }

            if let error = error {
                self.onError?(error)
                return
            }

            self.rewardedInterstitialAd = ad
            self.rewardedInterstitialAd?.fullScreenContentDelegate = self

        }
    }

    func stopLoading() {
        rewardedInterstitialAd?.fullScreenContentDelegate = nil
        rewardedInterstitialAd = nil
    }

    func show(from viewController: UIViewController,
              onOpen: (() -> Void)?,
              onClose: (() -> Void)?,
              onError: ((Error) -> Void)?,
              onReward: @escaping (NSDecimalNumber) -> Void) {
        self.onOpen = onOpen
        self.onClose = onClose
        self.onError = onError

        guard let rewardedInterstitialAd = rewardedInterstitialAd else {
            load()
            onError?(AdsError.rewardedInterstitialAdNotLoaded)
            return
        }

        do {
            try rewardedInterstitialAd.canPresent(fromRootViewController: viewController)
            let rewardAmount = rewardedInterstitialAd.adReward.amount
            rewardedInterstitialAd.present(fromRootViewController: viewController, userDidEarnRewardHandler: {
                onReward(rewardAmount)
            })
        } catch {
            load()
            onError?(error)
            return
        }
    }
}

// MARK: - GADFullScreenContentDelegate

extension AdsRewardedInterstitial: GADFullScreenContentDelegate {
    func adDidRecordImpression(_ ad: GADFullScreenPresentingAd) {
        print("AdsRewardedInterstitial did record impression for ad: \(ad)")
    }

    func adWillPresentFullScreenContent(_ ad: GADFullScreenPresentingAd) {
        isShowingRewardedInterstitialAd = true
        onOpen?()
    }

    func adDidDismissFullScreenContent(_ ad: GADFullScreenPresentingAd) {
        isShowingRewardedInterstitialAd = false
        // Nil out reference
        rewardedInterstitialAd = nil
        // Send callback
        onClose?()
        // Load the next ad so its ready for displaying
        load()
    }

    func ad(_ ad: GADFullScreenPresentingAd, didFailToPresentFullScreenContentWithError error: Error) {
        onError?(error)
    }
}
