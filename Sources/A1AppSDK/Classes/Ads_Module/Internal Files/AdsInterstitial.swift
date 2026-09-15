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

/// Loading, presenting and delegate handling all live in `AdsFullScreen`.
final class AdsInterstitial: AdsFullScreen, AdsInterstitialType {

    init(adUnitId: String, request: @escaping () -> GADRequest) {
        super.init(
            adUnitId: adUnitId,
            request: request,
            debugName: "AdsInterstitial",
            events: Events(loadStart: .event_ad_inter_load_start, loadFailed: .event_ad_inter_load_failed,
                           loaded: .event_ad_inter_loaded, showRequested: .event_ad_inter_show_requested,
                           shown: .event_ad_inter_shown, showFailed: .event_ad_inter_show_failed,
                           appError: AppErrorMessages(notLoaded: "Interstitial ad not loaded",
                                                      cantPresent: "Interstitial ad can't present")),
            notLoadedError: .interstitialAdNotLoaded,
            onDismiss: { AdsHandler.shared.interLoadTime = Date() },
            loader: { adUnitId, request, completion in
                GADInterstitialAd.load(withAdUnitID: adUnitId, request: request) { completion($0, $1) }
            }
        )
    }

    func show(from viewController: UIViewController,
              onOpen: (() -> Void)?,
              onClose: (() -> Void)?,
              onError: ((Error) -> Void)?) {
        showAd(from: viewController, onOpen: onOpen, onClose: onClose,
               onError: onError, onNotReady: nil, onReward: nil)
    }
}
