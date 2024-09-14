//
//  AdsInterstitial.swift
//  A1IOSLib
//
//  Created by Mohammad Zaid on 28/11/23.
//

import Foundation

import GoogleMobileAds

protocol AdsInterstitialType: AnyObject {
    var isReady: Bool { get }
    var isShowing: Bool { get }
    func load()
    func stopLoading()
    func show(from viewController: UIViewController,
              onOpen: (() -> Void)?,
              onClose: (() -> Void)?,
              onError: ((Error) -> Void)?)
}

final class AdsInterstitial: NSObject {

    // MARK: - Properties

    private let adUnitId: String
    private let request: () -> GADRequest
    
    private var onOpen: (() -> Void)?
    private var onClose: (() -> Void)?
    private var onError: ((Error) -> Void)?
    
    private var interstitialAd: GADInterstitialAd?
    private var isShowingInterAd = false

    // MARK: - Initialization
    
    init(adUnitId: String, request: @escaping () -> GADRequest) {
        self.adUnitId = adUnitId
        self.request = request
    }
}

// MARK: - AdsInterstitialType

extension AdsInterstitial: AdsInterstitialType {
    var isReady: Bool {
        interstitialAd != nil
    }
    
    var isShowing: Bool {
        isShowingInterAd
    }
    
    func load() {
        EventManager.shared.logEvent(title: AdsKey.event_ad_inter_load_start.rawValue)
        GADInterstitialAd.load(withAdUnitID: adUnitId, request: request()) { [weak self] (ad, error) in
            guard let self = self else { return }

            if let error = error {
                EventManager.shared.logEvent(title: AdsKey.event_ad_inter_load_failed.rawValue)
                EventManager.shared.logEvent(title: AppErrorKey.event_ad_error_load_failed.rawValue, key: "error", value: error.localizedDescription)
                self.onError?(error)
                return
            }
            EventManager.shared.logEvent(title: AdsKey.event_ad_inter_loaded.rawValue)
            self.interstitialAd = ad
            self.interstitialAd?.fullScreenContentDelegate = self
        }
    }

    func stopLoading() {
        interstitialAd?.fullScreenContentDelegate = nil
        interstitialAd = nil
    }
    
    func show(from viewController: UIViewController,
              onOpen: (() -> Void)?,
              onClose: (() -> Void)?,
              onError: ((Error) -> Void)?) {
        self.onOpen = onOpen
        self.onClose = onClose
        self.onError = onError
        EventManager.shared.logEvent(title: AdsKey.event_ad_inter_show_requested.rawValue)
        guard let interstitialAd = interstitialAd else {
            load()
            EventManager.shared.logEvent(title: AdsKey.event_ad_inter_show_failed.rawValue)
            EventManager.shared.logEvent(title: AppErrorKey.event_ad_error_show_failed.rawValue, key: "error", value: "Interstitial ad not loaded")
            onError?(AdsError.interstitialAdNotLoaded)
            return
        }

        do {
            try interstitialAd.canPresent(fromRootViewController: viewController)
            EventManager.shared.logEvent(title: AdsKey.event_ad_inter_shown.rawValue)
            interstitialAd.present(fromRootViewController: viewController)
        } catch {
            load()
            EventManager.shared.logEvent(title: AdsKey.event_ad_inter_show_failed.rawValue)
            EventManager.shared.logEvent(title: AppErrorKey.event_ad_error_show_failed.rawValue, key: "error", value: "Interstitial ad can't present")
            onError?(error)
        }
    }
}

// MARK: - GADFullScreenContentDelegate

extension AdsInterstitial: GADFullScreenContentDelegate {
    func adDidRecordImpression(_ ad: GADFullScreenPresentingAd) {
        print("AdsInterstitial did record impression for ad: \(ad)")
    }

    func adWillPresentFullScreenContent(_ ad: GADFullScreenPresentingAd) {
        isShowingInterAd = true
        onOpen?()
    }

    func adDidDismissFullScreenContent(_ ad: GADFullScreenPresentingAd) {
        // Nil out reference
        interstitialAd = nil
        isShowingInterAd = false
        // Send callback
        onClose?()
        AdsHandler.shared.interLoadTime = Date()
        // Load the next ad so its ready for displaying
        load()
    }

    func ad(_ ad: GADFullScreenPresentingAd, didFailToPresentFullScreenContentWithError error: Error) {
        EventManager.shared.logEvent(title: AdsKey.event_ad_inter_show_failed.rawValue)
        EventManager.shared.logEvent(title: AppErrorKey.event_ad_error_show_failed.rawValue, key: "error", value: error.localizedDescription)
        onError?(error)
    }
}
