//
//  A1PurchaseResult.swift
//  A1AppSDK
//

import Foundation

/// Outcome of a purchase or restore, with no vendor types in the signature.
public enum A1PurchaseResult {
    case success(A1Transaction)
    case cancelled
    /// Awaiting external action — Ask to Buy, SCA, or a pending store review.
    case pending
    case failed(A1PurchaseError)
}

/// The parts of a completed transaction the apps actually consume.
public struct A1Transaction {
    public let productIdentifier: String
    public let placement: A1Placement?
    /// `true` when entitlement is now active.
    public let isActive: Bool

    public init(productIdentifier: String, placement: A1Placement?, isActive: Bool) {
        self.productIdentifier = productIdentifier
        self.placement = placement
        self.isActive = isActive
    }
}

/// Vendor errors mapped into a stable, app-facing shape.
public enum A1PurchaseError: Error {
    case notConnected
    case paywallUnavailable
    case productsUnavailable
    case purchaseFailed(String)
    case restoreFailed(String)
    case nothingToRestore
    case renderingFailed(String)
    /// Anything the adapter could not classify. Message is preserved for logging.
    case unknown(String)

    public var localizedDescription: String {
        switch self {
        case .notConnected:               return "No internet connection"
        case .paywallUnavailable:         return "Paywall could not be loaded"
        case .productsUnavailable:        return "Products could not be loaded"
        case .purchaseFailed(let m):      return m
        case .restoreFailed(let m):       return m
        case .nothingToRestore:           return "Nothing to restore"
        case .renderingFailed(let m):     return m
        case .unknown(let m):             return m
        }
    }
}
