//
//  A1Placement.swift
//  A1AppSDK
//

import Foundation

/// Identifies a paywall placement.
///
/// Deliberately a `String`-backed struct rather than an enum: placement ids are configured
/// per app in the vendor dashboard and differ between apps, so the SDK must not close the
/// set. Each app declares its own in an extension:
///
/// ```swift
/// extension A1Placement {
///     static let settings = A1Placement("pro_pl_setting")
///     static let share    = A1Placement("pro_pl_share")
/// }
/// ```
public struct A1Placement: RawRepresentable, Hashable, ExpressibleByStringLiteral, CustomStringConvertible, Sendable {
    public let rawValue: String

    public init(rawValue: String) { self.rawValue = rawValue }
    public init(_ rawValue: String) { self.rawValue = rawValue }
    public init(stringLiteral value: String) { self.rawValue = value }

    public var description: String { rawValue }
}
