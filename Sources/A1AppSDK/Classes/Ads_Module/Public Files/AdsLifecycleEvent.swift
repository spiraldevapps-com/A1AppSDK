//
//  AdsLifecycleEvent.swift
//  A1AppSDK
//
//  Lifecycle events for every ad format, reported through `Ads.eventHandler`.
//  Added in 1.0.26 so apps can log loads, failures (with the SDK error),
//  impressions and clicks — which the show callbacks do not cover.
//

import Foundation

/// The ad format an event belongs to.
public enum AdsFormat: String {
    case appOpen = "app_open"
    case interstitial
    case rewarded
    case banner
}

public enum AdsLifecycleEvent {
    /// A load request was sent.
    case loadStarted(AdsFormat)
    /// An ad finished loading and is ready to show.
    case loaded(AdsFormat)
    /// A load failed. Carries the SDK error.
    case loadFailed(AdsFormat, Error)
    /// AdMob recorded an impression.
    case impression(AdsFormat)
    /// The user tapped the ad.
    case clicked(AdsFormat)
    /// A loaded ad could not be presented. Carries the SDK error.
    case presentFailed(AdsFormat, Error)
    /// A loaded app open ad passed `Ads.appOpenExpiry` and was discarded unused.
    case expired(AdsFormat)
}
