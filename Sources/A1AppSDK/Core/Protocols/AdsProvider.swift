//
//  AdsProvider.swift
//  A1AppSDK
//

import Foundation
import UIKit

/// A presented banner, controlled without touching the ad vendor's view type.
public protocol A1BannerAd: AnyObject {
    /// The view to insert into the host's hierarchy.
    var containerView: UIView { get }
    func show()
    func remove()
    func updateLayout()
}

/// Callbacks for a full-screen ad presentation.
public struct A1AdCallbacks {
    public var onOpen: (() -> Void)?
    public var onClose: (() -> Void)?
    public var onError: ((Error) -> Void)?
    /// Rewarded formats only.
    public var onReward: ((NSDecimalNumber) -> Void)?
    /// Requested format was not loaded. Lets the caller proceed rather than stall.
    public var onNotReady: (() -> Void)?

    public init(onOpen: (() -> Void)? = nil,
                onClose: (() -> Void)? = nil,
                onError: ((Error) -> Void)? = nil,
                onReward: ((NSDecimalNumber) -> Void)? = nil,
                onNotReady: (() -> Void)? = nil) {
        self.onOpen = onOpen
        self.onClose = onClose
        self.onError = onError
        self.onReward = onReward
        self.onNotReady = onNotReady
    }
}

/// The ad engine.
///
/// Frequency capping and pro/consent gating live behind `canShow(_:)` so every app applies
/// the same tuned policy instead of re-deriving it.
public protocol AdsProvider: AnyObject {

    /// Apply remote configuration and entitlement. Safe to call repeatedly; the
    /// implementation reconfigures only when something material changed.
    func configure(_ configuration: AdsConfiguration, isPro: Bool)

    /// Current lifecycle state of a format.
    func state(for format: A1AdFormat) -> A1AdState

    /// Whether a format may be shown right now.
    /// Returns `nil` when it may; otherwise the reason it may not.
    func suppressionReason(for format: A1AdFormat) -> A1AdSuppressionReason?

    /// Convenience over `suppressionReason(for:)`.
    func canShow(_ format: A1AdFormat) -> Bool

    /// Present a full-screen format.
    func show(_ format: A1AdFormat,
              from viewController: UIViewController,
              callbacks: A1AdCallbacks)

    /// Build a banner for the given controller. `nil` when banners are unavailable.
    func makeBanner(in viewController: UIViewController,
                    callbacks: A1AdCallbacks) -> A1BannerAd?

    /// Globally enable/disable. Disabling stops all loading and releases loaded ads.
    func setDisabled(_ isDisabled: Bool)
}

public extension AdsProvider {
    func canShow(_ format: A1AdFormat) -> Bool {
        suppressionReason(for: format) == nil
    }
}
