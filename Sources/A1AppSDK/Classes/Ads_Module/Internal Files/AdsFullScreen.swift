//
//  AdsFullScreen.swift
//  A1IOSLib
//
//  Shared implementation behind AdsInterstitial, AdsRewarded and AdsRewardedInterstitial.
//  Those three only differ in which Google ad type they load, which analytics keys they log
//  and whether they hand back a reward, so the state keeping, presentation and
//  GADFullScreenContentDelegate handling live here once instead of three times.
//

import Foundation
import GoogleMobileAds

/// The slice of `GADInterstitialAd` / `GADRewardedAd` / `GADRewardedInterstitialAd` that
/// `AdsFullScreen` drives. The SDK gives those three no common base class, only this shape.
protocol AdsFullScreenPresentable: AnyObject {
    var fullScreenContentDelegate: GADFullScreenContentDelegate? { get set }
    func canPresent(fromRootViewController rootViewController: UIViewController?) throws
    func present(from viewController: UIViewController, onReward: ((NSDecimalNumber) -> Void)?)
}

extension GADInterstitialAd: AdsFullScreenPresentable {
    func present(from viewController: UIViewController, onReward: ((NSDecimalNumber) -> Void)?) {
        present(fromRootViewController: viewController)
    }
}

extension GADRewardedAd: AdsFullScreenPresentable {
    func present(from viewController: UIViewController, onReward: ((NSDecimalNumber) -> Void)?) {
        // Reward amount is read before presenting, as the original call sites did.
        let rewardAmount = adReward.amount
        present(fromRootViewController: viewController) { onReward?(rewardAmount) }
    }
}

extension GADRewardedInterstitialAd: AdsFullScreenPresentable {
    func present(from viewController: UIViewController, onReward: ((NSDecimalNumber) -> Void)?) {
        let rewardAmount = adReward.amount
        present(fromRootViewController: viewController) { onReward?(rewardAmount) }
    }
}

class AdsFullScreen: NSObject {

    /// Failure descriptions. Only the interstitial mirrors its failures into `AppErrorKey`;
    /// a nil value means this format sends no AppError events at all.
    struct AppErrorMessages {
        let notLoaded: String
        let cantPresent: String
    }

    /// Analytics keys for one format. Every field is optional because the formats deliberately
    /// log different subsets — the rewarded interstitial logs nothing.
    struct Events {
        var loadStart: AdsKey?
        var loadFailed: AdsKey?
        var loaded: AdsKey?
        var showRequested: AdsKey?
        var shown: AdsKey?
        var showFailed: AdsKey?
        var appError: AppErrorMessages?
    }

    typealias Loader = (String, GADRequest, @escaping (AdsFullScreenPresentable?, Error?) -> Void) -> Void

    // MARK: - Properties

    private let adUnitId: String
    private let request: () -> GADRequest
    private let debugName: String
    private let events: Events
    private let notLoadedError: AdsError
    /// Extra work on dismissal: the interstitial stamps `AdsHandler.shared.interLoadTime`.
    private let onDismiss: (() -> Void)?
    private let loader: Loader

    private var ad: AdsFullScreenPresentable?
    private var isPresenting = false

    private var onOpen: (() -> Void)?
    private var onClose: (() -> Void)?
    private var onError: ((Error) -> Void)?

    // MARK: - Initialization

    init(adUnitId: String,
         request: @escaping () -> GADRequest,
         debugName: String,
         events: Events,
         notLoadedError: AdsError,
         onDismiss: (() -> Void)? = nil,
         loader: @escaping Loader) {
        self.adUnitId = adUnitId
        self.request = request
        self.debugName = debugName
        self.events = events
        self.notLoadedError = notLoadedError
        self.onDismiss = onDismiss
        self.loader = loader
    }

    // MARK: - Lifecycle

    var isReady: Bool { ad != nil }

    var isShowing: Bool { isPresenting }

    func load() {
        log(events.loadStart)
        loader(adUnitId, request()) { [weak self] ad, error in
            guard let self = self else { return }

            if let error = error {
                self.log(self.events.loadFailed)
                if self.events.appError != nil {
                    self.log(.event_ad_error_load_failed, error.localizedDescription)
                }
                self.onError?(error)
                return
            }
            self.log(self.events.loaded)
            self.ad = ad
            self.ad?.fullScreenContentDelegate = self
        }
    }

    func stopLoading() {
        ad?.fullScreenContentDelegate = nil
        ad = nil
    }

    /// Backs the `show` method each format exposes through its own protocol.
    func showAd(from viewController: UIViewController,
                onOpen: (() -> Void)?,
                onClose: (() -> Void)?,
                onError: ((Error) -> Void)?,
                onNotReady: (() -> Void)?,
                onReward: ((NSDecimalNumber) -> Void)?) {
        self.onOpen = onOpen
        self.onClose = onClose
        self.onError = onError
        log(events.showRequested)

        guard let ad = ad else {
            load()
            log(events.showFailed)
            log(.event_ad_error_show_failed, events.appError?.notLoaded)
            onError?(notLoadedError)
            onNotReady?()
            return
        }

        do {
            try ad.canPresent(fromRootViewController: viewController)
            log(events.shown)
            ad.present(from: viewController, onReward: onReward)
        } catch {
            load()
            log(events.showFailed)
            log(.event_ad_error_show_failed, events.appError?.cantPresent)
            onError?(error)
            onNotReady?()
        }
    }

    // MARK: - Analytics

    private func log(_ key: AdsKey?) {
        guard let key = key else { return }
        EventManager.shared.logEvent(title: key.rawValue)
    }

    private func log(_ key: AppErrorKey, _ message: String?) {
        guard let message = message else { return }
        EventManager.shared.logEvent(title: key.rawValue, key: "error", value: message)
    }
}

// MARK: - GADFullScreenContentDelegate

extension AdsFullScreen: GADFullScreenContentDelegate {
    func adDidRecordImpression(_ ad: GADFullScreenPresentingAd) {
        print("\(debugName) did record impression for ad: \(ad)")
    }

    func adWillPresentFullScreenContent(_ ad: GADFullScreenPresentingAd) {
        isPresenting = true
        onOpen?()
    }

    func adDidDismissFullScreenContent(_ ad: GADFullScreenPresentingAd) {
        // Nil out reference
        self.ad = nil
        isPresenting = false
        // Send callback
        onClose?()
        onDismiss?()
        // Load the next ad so its ready for displaying
        load()
    }

    func ad(_ ad: GADFullScreenPresentingAd, didFailToPresentFullScreenContentWithError error: Error) {
        log(events.showFailed)
        if events.appError != nil {
            log(.event_ad_error_show_failed, error.localizedDescription)
        }
        onError?(error)
    }
}
