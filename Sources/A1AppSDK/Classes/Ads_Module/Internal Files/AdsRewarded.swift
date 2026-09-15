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

/// Loading, presenting and delegate handling all live in `AdsFullScreen`.
final class AdsRewarded: AdsFullScreen, AdsRewardedType {

    init(adUnitId: String, request: @escaping () -> GADRequest) {
        super.init(
            adUnitId: adUnitId,
            request: request,
            debugName: "AdsRewarded",
            events: Events(loadStart: .event_ad_rewarded_load_start, loadFailed: .event_ad_rewarded_load_failed,
                           loaded: .event_ad_rewarded_loaded, showRequested: .event_ad_rewarded_show_requested,
                           shown: .event_ad_rewarded_shown, showFailed: .event_ad_rewarded_show_failed),
            notLoadedError: .rewardedAdNotLoaded,
            loader: { adUnitId, request, completion in
                GADRewardedAd.load(withAdUnitID: adUnitId, request: request) { completion($0, $1) }
            }
        )
    }

    func show(from viewController: UIViewController,
              onOpen: (() -> Void)?,
              onClose: (() -> Void)?,
              onError: ((Error) -> Void)?,
              onNotReady: (() -> Void)?,
              onReward: @escaping (NSDecimalNumber) -> Void) {
        showAd(from: viewController, onOpen: onOpen, onClose: onClose,
               onError: onError, onNotReady: onNotReady, onReward: onReward)
    }
}
