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

/// Loading, presenting and delegate handling all live in `AdsFullScreen`.
/// This format deliberately logs no analytics events, hence the empty `Events`.
final class AdsRewardedInterstitial: AdsFullScreen, AdsRewardedInterstitialType {

    init(adUnitId: String, request: @escaping () -> GADRequest) {
        super.init(
            adUnitId: adUnitId,
            request: request,
            debugName: "AdsRewardedInterstitial",
            events: Events(),
            notLoadedError: .rewardedInterstitialAdNotLoaded,
            loader: { adUnitId, request, completion in
                GADRewardedInterstitialAd.load(withAdUnitID: adUnitId, request: request) { completion($0, $1) }
            }
        )
    }

    func show(from viewController: UIViewController,
              onOpen: (() -> Void)?,
              onClose: (() -> Void)?,
              onError: ((Error) -> Void)?,
              onReward: @escaping (NSDecimalNumber) -> Void) {
        showAd(from: viewController, onOpen: onOpen, onClose: onClose,
               onError: onError, onNotReady: nil, onReward: onReward)
    }
}
