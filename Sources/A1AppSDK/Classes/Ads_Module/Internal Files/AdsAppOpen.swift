//
//  AdsAppOpen.swift
//  A1IOSLib
//
//  Created by Mohammad Zaid on 29/11/23.
//

import Foundation

import GoogleMobileAds

protocol AdsAppOpenType: AnyObject {
    var isAppOpenSplash: Bool { get set }
    var isReady: Bool { get }
    var isShowing: Bool { get }
    var isLoading: Bool { get }
    func load()
    func stopLoading()
    func show(from viewController: UIViewController,
              onOpen: (() -> Void)?,
              onClose: (() -> Void)?,
              onError: ((Error) -> Void)?)
}

final class AppOpenAdManager: NSObject {

    // MARK: - Properties

    private let adUnitId: String
    private let request: () -> GADRequest

    private var appOpenAd: GADAppOpenAd?
    private var isLoadingAd = false
    private var isShowingAd = false
    var isAppOpenSplash = false

    /// Set when a show was requested before the ad was ready: the load completion
    /// presents it from `viewController` as soon as the ad arrives.
    private var showAdAfterLoad = false
    private var viewController: UIViewController?

    private var onOpen: (() -> Void)?
    private var onClose: (() -> Void)?
    private var onError: ((Error) -> Void)?

    // MARK: - Initialization

    init(adUnitId: String, request: @escaping () -> GADRequest) {
        self.adUnitId = adUnitId
        self.request = request
    }

    /// Console diagnostics only. Compiled out of release builds, so the message is never built.
    private func debugLog(_ message: @autoclosure () -> String) {
        #if DEBUG
        print(message())
        #endif
    }

    // MARK: - Convenience

    func loadAd() {
        // Do not load ad if there is an unused ad or one is already loading.
        if isLoadingAd || appOpenAd != nil { return }

        EventManager.shared.logEvent(title: AdsKey.event_ad_appopen_load_start.rawValue)
        isLoadingAd = true
        debugLog("Start loading app open ad.")
        GADAppOpenAd.load(withAdUnitID: adUnitId, request: request()) { [weak self] (ad, error) in
            guard let self else { return }
            self.isLoadingAd = false
            if let error = error {
                self.appOpenAd = nil
                self.debugLog("App open ad failed to load with error: \(error.localizedDescription)")
                EventManager.shared.logEvent(title: AdsKey.event_ad_appopen_load_failed.rawValue)
                EventManager.shared.logEvent(title: AppErrorKey.event_ad_error_load_failed.rawValue, key: "error", value: error.localizedDescription)
                self.onError?(error)
                return
            }
            EventManager.shared.logEvent(title: AdsKey.event_ad_appopen_loaded.rawValue)
            self.appOpenAd = ad
            ad?.fullScreenContentDelegate = self
            self.debugLog("App open ad loaded successfully.")
            if self.showAdAfterLoad, let ad, let viewController = self.viewController {
                self.isShowingAd = true
                self.showAdAfterLoad = false
                ad.present(fromRootViewController: viewController)
                EventManager.shared.logEvent(title: AdsKey.event_ad_appopen_shown.rawValue)
                self.viewController = nil
            }
        }
    }

    func showAdIfAvailable(viewController: UIViewController,
                           onOpen: (() -> Void)?,
                           onClose: (() -> Void)?,
                           onError: ((Error) -> Void)?) {
        self.onOpen = onOpen
        self.onClose = onClose
        self.onError = onError
        self.viewController = viewController
        self.showAdAfterLoad = true
        EventManager.shared.logEvent(title: AdsKey.event_ad_appopen_show_requested.rawValue)

        // If the app open ad is already showing, do not show the ad again.
        if isShowingAd {
            debugLog("App open ad is already showing.")
            return
        }
        // Not ready yet: start a load. `showAdAfterLoad` stays true, so the load
        // completion presents the ad as soon as it arrives.
        guard let ad = appOpenAd else {
            debugLog("App open ad is not ready yet.")
            loadAd()
            return
        }
        debugLog("App open ad will be displayed.")
        isShowingAd = true
        showAdAfterLoad = false
        EventManager.shared.logEvent(title: AdsKey.event_ad_appopen_shown.rawValue)
        ad.present(fromRootViewController: viewController)
    }
}

// MARK: - GADFullScreenContentDelegate

extension AppOpenAdManager: GADFullScreenContentDelegate {
    func adWillPresentFullScreenContent(_ ad: GADFullScreenPresentingAd) {
        debugLog("App open ad is will be presented.")
        onOpen?()
    }

    func adDidDismissFullScreenContent(_ ad: GADFullScreenPresentingAd) {
        appOpenAd = nil
        isShowingAd = false
        debugLog("App open ad was dismissed.")
        onClose?()
        AdsHandler.shared.appOpenLoadTime = Date()
        // Load the next ad so its ready for displaying
        loadAd()
    }

    func ad(
        _ ad: GADFullScreenPresentingAd,
        didFailToPresentFullScreenContentWithError error: Error
    ) {
        // Note: `appOpenAd` is deliberately not cleared here; only reloaded if it is already nil.
        isShowingAd = false
        EventManager.shared.logEvent(title: AdsKey.event_ad_appopen_show_failed.rawValue)
        EventManager.shared.logEvent(title: AppErrorKey.event_ad_error_show_failed.rawValue, key: "error", value: error.localizedDescription)
        debugLog("App open ad failed to present with error: \(error.localizedDescription)")
        if appOpenAd == nil {
            loadAd()
        }
        onError?(error)
    }
}

extension AppOpenAdManager: AdsAppOpenType {
    var isReady: Bool { appOpenAd != nil }

    var isShowing: Bool { isShowingAd }

    var isLoading: Bool { isLoadingAd }

    func load() {
        loadAd()
    }

    func stopLoading() {
        appOpenAd?.fullScreenContentDelegate = nil
        appOpenAd = nil
    }

    func show(from viewController: UIViewController, onOpen: (() -> Void)?, onClose: (() -> Void)?, onError: ((Error) -> Void)?) {
        showAdIfAvailable(viewController: viewController, onOpen: onOpen, onClose: onClose, onError: onError)
    }
}
