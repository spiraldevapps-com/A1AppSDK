//
//  AdsError.swift
//  A1IOSLib
//
//  Created by Mohammad Zaid on 28/11/23.
//

import Foundation

public enum AdsError: Error {
    case appOpenAdNotLoaded
    case interstitialAdNotLoaded
    case rewardedAdNotLoaded
    case rewardedInterstitialAdNotLoaded
    case bannerAdMissingAdUnitId

    public var errorDescription: String? {
        switch self {
        case .appOpenAdNotLoaded:
            return "App Open ad not loaded"
        case .interstitialAdNotLoaded:
            return "Interstitial ad not loaded"
        case .rewardedAdNotLoaded:
            return "Rewarded ad not loaded"
        case .rewardedInterstitialAdNotLoaded:
            return "Rewarded interstitial ad not loaded"
        case .bannerAdMissingAdUnitId:
            return "Banner ad has no AdUnitId"
        }
    }
}
