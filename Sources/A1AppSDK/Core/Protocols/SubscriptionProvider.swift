//
//  SubscriptionProvider.swift
//  A1AppSDK
//

import Foundation
import UIKit

/// Callbacks for a presented paywall.
///
/// A struct of closures rather than a delegate protocol: the host app sets only what it
/// cares about, and there is no delegate reference to retain or forget to clear.
public struct A1PaywallCallbacks {
    /// Loader should be shown/hidden.
    public var onLoading: ((Bool) -> Void)?
    /// Load, render or purchase failed. Present the message to the user.
    public var onError: ((A1PurchaseError) -> Void)?
    /// A purchase finished, in any outcome.
    public var onPurchase: ((A1PurchaseResult) -> Void)?
    /// A restore finished.
    public var onRestore: ((A1PurchaseResult) -> Void)?
    /// User dismissed the paywall without buying.
    public var onClose: (() -> Void)?
    /// Paywall finished dismissing, whatever the outcome. Fires exactly once.
    public var onDismiss: (() -> Void)?

    public init(onLoading: ((Bool) -> Void)? = nil,
                onError: ((A1PurchaseError) -> Void)? = nil,
                onPurchase: ((A1PurchaseResult) -> Void)? = nil,
                onRestore: ((A1PurchaseResult) -> Void)? = nil,
                onClose: (() -> Void)? = nil,
                onDismiss: (() -> Void)? = nil) {
        self.onLoading = onLoading
        self.onError = onError
        self.onPurchase = onPurchase
        self.onRestore = onRestore
        self.onClose = onClose
        self.onDismiss = onDismiss
    }
}

/// The subscription engine, with no vendor types in any signature.
///
/// Swapping the vendor means writing a new conformer and registering it. Host apps
/// see only this protocol and the `A1*` models, so they do not change.
public protocol SubscriptionProvider: AnyObject {

    /// Whether the user currently holds the premium entitlement.
    /// Reads a cached value — safe to call on the main thread during layout.
    var isPro: Bool { get }

    /// Re-check entitlement with the vendor. Called at launch and after any purchase.
    func refreshEntitlement(completion: ((Bool) -> Void)?)

    /// Observe entitlement changes. Fires immediately with the current value.
    /// This is how the ads layer learns to switch itself off.
    @discardableResult
    func observeEntitlement(_ handler: @escaping (Bool) -> Void) -> A1ObservationToken

    /// Resolve how a placement wants to be presented, without presenting it.
    /// Use when the app needs to render the paywall itself.
    func paywall(for placement: A1Placement,
                 completion: @escaping (Result<A1PaywallConfig, A1PurchaseError>) -> Void)

    /// Resolve and present a placement. The common path.
    func present(_ placement: A1Placement,
                 from viewController: UIViewController,
                 callbacks: A1PaywallCallbacks)

    /// Warm the cache so presentation is instant. Typically called once at launch.
    func prefetch(_ placements: [A1Placement])

    /// Restore previous purchases outside of a paywall.
    func restore(completion: @escaping (A1PurchaseResult) -> Void)

    /// Attach a third-party id (Meta anonymous id, Firebase app instance id, …) for
    /// revenue attribution. Key/value are vendor-defined strings.
    func setIntegrationIdentifier(key: String, value: String)
}
