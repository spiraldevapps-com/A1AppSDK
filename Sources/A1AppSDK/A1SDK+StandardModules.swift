//
//  A1SDK+StandardModules.swift
//  A1AppSDK
//
//  The stock set of frameworks the SDK owns, and the one-line way to adopt them.
//
//  ⚠️ Everything in this file runs at REGISTRATION time, not at boot.
//
//  `standardModules()` constructs every adapter in a single array literal, and the host app
//  calls it before `A1SDK.configure(with:)`. So every one of these initialisers — including
//  stored-property initialisers — runs before `FirebaseApp.configure()`, before Adapty,
//  before AdMob, before everything. A module whose `init` touches its vendor crashes the app
//  on launch here; that is exactly how the `FIRAppNotConfigured` crash happened.
//
//  Boot phases order `configure(context:)`. They do not order construction. See `A1Module`
//  for the contract every adapter listed below must keep.
//

import Foundation

public extension A1SDK {

    /// Every framework A1AppSDK ships, in one call.
    ///
    /// A module whose configuration is absent does nothing: no AppMetrica key means no
    /// AppMetrica, no Clarity project id means no session recording, and so on. So an app
    /// registers the full set and opts in purely through `A1Configuration`.
    ///
    /// ```swift
    /// // AppDelegate — the whole of it.
    /// A1SDK.shared.register(A1SDK.standardModules())
    /// A1SDK.shared.register(MyOwnFrameworkModule())   // anything else you want
    /// A1SDK.shared.configure(with: configuration)
    /// ```
    ///
    /// Boot order comes from each module's `phase`, not from this array's order.
    ///
    /// The returned modules are constructed but *not* configured — none of them has touched
    /// a vendor yet, and none may until `configure(with:)` reaches it.
    static func standardModules() -> [A1Module] {
        standardModuleBuilders().map { $0.make() }
    }

    /// The stock set minus the modules an app does not want.
    ///
    /// Excluded modules are never constructed, so excluding one keeps its `init` off the
    /// launch path entirely.
    ///
    /// ```swift
    /// A1SDK.shared.register(A1SDK.standardModules(excluding: [IntercomAdapter.self]))
    /// ```
    static func standardModules(excluding excluded: [Any.Type]) -> [A1Module] {
        let names = Set(excluded.map { String(describing: $0) })
        return standardModuleBuilders()
            .filter { !names.contains($0.name) }
            .map { $0.make() }
    }

    // MARK: - Internals

    /// The stock set as name/constructor pairs, so `excluding:` can drop a module without
    /// building it first. The name is derived from the type itself, so it cannot drift from
    /// the `moduleIdentifier` default (`String(describing: type(of: self))`).
    private static func standardModuleBuilders() -> [(name: String, make: () -> A1Module)] {
        [
            // .bootstrap — Firebase before everything that depends on it.
            builder { FirebaseCoreAdapter() },

            // .foundation — Meta needs the original launch options.
            builder { MetaAdapter() },
            builder { ReachabilityAdapter() },
            builder { TrackingAdapter() },
            builder { AttributionAdapter() },

            // .identity
            builder { FirebaseAuthAdapter() },
            builder { StoreKitAdapter() },

            // .remoteConfig
            builder { RemoteConfigAdapter() },
            builder { AppUpdateAdapter() },

            // .analytics
            builder { FirebaseAnalyticsAdapter() },
            builder { AppMetricaAdapter() },
            builder { ClarityAdapter() },
            builder { PerformanceAdapter() },

            // .monetization
            builder { AdaptyAdapter() },

            // consent, then advertising
            builder { ConsentAdapter() },
            builder { AdMobAdapter() },

            // .support
            builder { IntercomAdapter() },
            builder { RatingAdapter() },

            // .notifications
            builder { MessagingAdapter() }
        ]
    }

    private static func builder<T: A1Module>(_ make: @escaping () -> T) -> (name: String, make: () -> A1Module) {
        (String(describing: T.self), { make() })
    }
}
