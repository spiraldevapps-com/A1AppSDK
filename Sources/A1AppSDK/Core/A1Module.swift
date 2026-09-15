//
//  A1Module.swift
//  A1AppSDK
//
//  The unit of extensibility. Every third-party framework the SDK owns is expressed
//  as an A1Module, and any host app can add a framework of its own the same way.
//
//  THE ONE RULE: a module's initialiser must be inert.
//
//  `A1BootPhase` orders `configure(context:)` calls. It does not — and cannot — order
//  *construction*. Modules are built by the host app at `register(_:)` time, all of them,
//  before `configure(with:)` has run and therefore before any vendor has been bootstrapped.
//  A stored-property initialiser is part of construction, so
//
//      private let remoteConfig = RemoteConfig.remoteConfig()   // WRONG
//
//  runs a Firebase call before `FirebaseApp.configure()` and crashes the app on launch.
//  This shipped once; do not let it ship again. The rules are spelled out on `A1Module` below.
//

import Foundation
import UIKit

/// Ordered boot stages.
///
/// Raw values are spaced so a host app can slot a custom module between two built-in
/// stages without this enum having to change (see `A1BootPhase.custom(after:)`).
///
/// The ordering encodes hard dependencies observed in production:
/// Firebase must exist before anything reads Remote Config or logs an event;
/// identity is established before SDKs that segment by user; remote config lands
/// before ads are configured; consent is gathered before ads load.
public struct A1BootPhase: RawRepresentable, Comparable, Hashable, Sendable {
    public let rawValue: Int
    public init(rawValue: Int) { self.rawValue = rawValue }

    /// Before everything. Reserved for the one dependency other modules cannot start
    /// without — `FirebaseApp.configure()` in practice.
    public static let bootstrap     = A1BootPhase(rawValue: 50)
    public static let foundation    = A1BootPhase(rawValue: 100)
    public static let identity      = A1BootPhase(rawValue: 200)
    public static let remoteConfig  = A1BootPhase(rawValue: 300)
    public static let analytics     = A1BootPhase(rawValue: 400)
    public static let monetization  = A1BootPhase(rawValue: 500)
    public static let advertising   = A1BootPhase(rawValue: 600)
    public static let support       = A1BootPhase(rawValue: 700)
    public static let notifications = A1BootPhase(rawValue: 800)

    /// Slot a custom module immediately after a built-in phase.
    public static func custom(after phase: A1BootPhase, offset: Int = 1) -> A1BootPhase {
        A1BootPhase(rawValue: phase.rawValue + offset)
    }

    public static func < (lhs: A1BootPhase, rhs: A1BootPhase) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

/// Everything a module is handed at boot.
public struct A1ModuleContext {
    /// App-supplied keys and feature switches.
    public let configuration: A1Configuration
    /// Shared identity. Modules that carry a user id should observe this rather than
    /// reading it once — on a first launch the id is empty until sign-in resolves.
    public let identity: A1Identity
    /// Event sink, so a module can report its own lifecycle without importing an analytics vendor.
    ///
    /// Always non-nil. Modules booting before the analytics phase get a proxy that buffers
    /// their events and flushes once a real sink attaches, so early boot events are not lost.
    public let analytics: AnalyticsProvider

    public init(configuration: A1Configuration, identity: A1Identity, analytics: AnalyticsProvider) {
        self.configuration = configuration
        self.identity = identity
        self.analytics = analytics
    }
}

/// A framework owned by the SDK.
///
/// Conform, declare a phase, register it with `A1SDK.shared.register(_:)`, and the
/// orchestrator boots it in the right order.
///
/// ## Contract
///
/// 1. **`init` and every stored-property initialiser must be inert.** Store plain values —
///    a key, a flag, a closure. No vendor call, and no singleton access that lazily creates
///    vendor state (`RemoteConfig.remoteConfig()`, `Messaging.messaging()`, `Adapty.…`,
///    `Intercom.…`, `AppMetrica.…`, `MobileAds.…`, `SKPaymentQueue.default()`, starting an
///    `NWPathMonitor`, …). Construction happens at registration, long before any vendor exists.
/// 2. **Resolve vendor objects in `configure(context:)`.** Hold them as optionals, or create
///    them on demand once boot has happened.
/// 3. **Guard, do not assume, another module's vendor.** Phase order usually puts Firebase
///    first, but a host app may register a subset. Anything needing Firebase checks
///    `FirebaseApp.app() != nil` and degrades quietly through `context.analytics.reportError`
///    rather than trapping.
/// 4. **Public accessors must be safe before boot.** A host app can reach a module through
///    `A1SDK.shared.module(_:)` at any time, including before `configure(with:)`. Such a call
///    returns a sane default; it never crashes and never lazily creates vendor state.
public protocol A1Module: AnyObject {
    /// Stable identifier, used for de-duplication and diagnostics.
    var moduleIdentifier: String { get }
    /// When this module boots relative to the others.
    ///
    /// Read before the module is configured, so its implementation must be a plain
    /// constant — never a vendor lookup.
    var phase: A1BootPhase { get }
    /// Perform vendor setup. Called once, on the main thread, in phase order.
    ///
    /// This — not `init` — is the earliest point at which touching a vendor SDK is legal.
    func configure(context: A1ModuleContext)
}

public extension A1Module {
    var moduleIdentifier: String { String(describing: type(of: self)) }
}

/// Opt in to `UIApplicationDelegate` forwarding.
///
/// Implement only what the vendor needs; every method has a no-op default. This is what
/// lets a host app's AppDelegate stop calling vendor SDKs directly.
public protocol A1LifecycleObserving: AnyObject {
    func applicationDidFinishLaunching(_ application: UIApplication,
                                       launchOptions: [UIApplication.LaunchOptionsKey: Any]?)
    func applicationDidBecomeActive(_ application: UIApplication)
    /// Return `true` if this module handled the URL.
    func application(_ application: UIApplication,
                     open url: URL,
                     options: [UIApplication.OpenURLOptionsKey: Any]) -> Bool
    func didRegisterForRemoteNotifications(deviceToken: Data)
}

public extension A1LifecycleObserving {
    func applicationDidFinishLaunching(_ application: UIApplication,
                                       launchOptions: [UIApplication.LaunchOptionsKey: Any]?) {}
    func applicationDidBecomeActive(_ application: UIApplication) {}
    func application(_ application: UIApplication,
                     open url: URL,
                     options: [UIApplication.OpenURLOptionsKey: Any]) -> Bool { false }
    func didRegisterForRemoteNotifications(deviceToken: Data) {}
}
