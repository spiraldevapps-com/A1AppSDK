//
//  A1AdState.swift
//  A1AppSDK
//

import Foundation

/// The ad formats the SDK supports.
public enum A1AdFormat: String, CaseIterable, Sendable {
    case appOpen
    case interstitial
    case banner
    case rewarded
    case rewardedInterstitial
    case native
}

/// Lifecycle state of a single ad format.
public struct A1AdState: Sendable {
    public let format: A1AdFormat
    /// Loaded and available to present.
    public let isReady: Bool
    /// Currently on screen.
    public let isShowing: Bool
    /// A load is in flight.
    public let isLoading: Bool

    public init(format: A1AdFormat, isReady: Bool, isShowing: Bool, isLoading: Bool = false) {
        self.format = format
        self.isReady = isReady
        self.isShowing = isShowing
        self.isLoading = isLoading
    }

    public static func idle(_ format: A1AdFormat) -> A1AdState {
        A1AdState(format: format, isReady: false, isShowing: false, isLoading: false)
    }
}

/// Why an ad was not shown. Useful for the debug screens the apps already ship.
public enum A1AdSuppressionReason: Sendable {
    case adsDisabled
    case userIsPro
    case formatDisabled
    case notConnected
    case notLoaded
    case anotherAdShowing
    /// Frequency cap not yet satisfied.
    case withinInterval
}
