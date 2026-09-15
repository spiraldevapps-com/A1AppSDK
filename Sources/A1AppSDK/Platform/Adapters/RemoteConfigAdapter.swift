//
//  RemoteConfigAdapter.swift
//  A1AppSDK
//

import Foundation
import FirebaseCore
import FirebaseRemoteConfig

/// Firebase Remote Config.
///
/// Intentionally generic. Each app has its own config schema — the SDK owns fetching and
/// decoding mechanics, the app owns its `Codable` shape. `AdsConfiguration` is the one
/// shared model, and apps decode it out of whatever key their payload nests it under.
public final class RemoteConfigAdapter: A1Module {

    public var phase: A1BootPhase { .remoteConfig }

    /// Seconds before a cached fetch is considered stale.
    /// Set to `0` in debug builds to see dashboard changes immediately.
    public var minimumFetchInterval: TimeInterval

    /// Resolved in `configure(context:)`, never at construction.
    ///
    /// `RemoteConfig.remoteConfig()` throws `FIRAppNotConfigured` if Firebase has not been
    /// configured yet, and `A1SDK.standardModules()` builds every module up front — long before
    /// the bootstrap phase runs `FirebaseApp.configure()`. A module's initialiser must stay inert.
    private var remoteConfig: RemoteConfig?
    private var analytics: AnalyticsProvider?

    /// Defaults handed in before this module booted, applied once Remote Config exists.
    private var pendingDefaults: [String: NSObject] = [:]

    public init(minimumFetchInterval: TimeInterval = 3600) {
        self.minimumFetchInterval = minimumFetchInterval
    }

    public func configure(context: A1ModuleContext) {
        analytics = context.analytics

        guard FirebaseApp.app() != nil else {
            context.analytics.reportError("a1sdk_remoteconfig_no_firebase",
                                          message: "FirebaseApp is not configured; Remote Config disabled",
                                          parameters: nil)
            return
        }

        let config = RemoteConfig.remoteConfig()
        let settings = RemoteConfigSettings()
        settings.minimumFetchInterval = minimumFetchInterval
        config.configSettings = settings
        remoteConfig = config

        if !pendingDefaults.isEmpty {
            config.setDefaults(pendingDefaults)
            pendingDefaults.removeAll()
        }
    }

    /// Fetch and activate. Completion reports whether new values were applied.
    public func refresh(completion: ((Result<Bool, Error>) -> Void)? = nil) {
        let started = CFAbsoluteTimeGetCurrent()

        guard let remoteConfig else {
            completion?(.success(false))
            return
        }

        remoteConfig.fetchAndActivate { [weak self] status, error in
            let elapsed = CFAbsoluteTimeGetCurrent() - started

            if let error {
                self?.analytics?.reportError("firebase_remoteconfig_error",
                                             message: error.localizedDescription,
                                             parameters: nil)
                completion?(.failure(error))
                return
            }

            let didChange = status == .successFetchedFromRemote
            self?.analytics?.log(A1Event("remote_config_fetch_successful",
                                         parameters: ["timeTaken": String(format: "%.3fs", elapsed)]))
            completion?(.success(didChange))
        }
    }

    // MARK: - Typed access

    /// Decode a JSON-valued key into a model.
    ///
    /// Returns `nil` rather than throwing — a malformed remote payload must never be able
    /// to break launch. Callers fall back to their built-in defaults, the same convention
    /// `AdsConfiguration` uses.
    public func decode<T: Decodable>(_ type: T.Type = T.self, forKey key: String) -> T? {
        guard let remoteConfig else { return nil }
        let data = remoteConfig[key].dataValue
        guard !data.isEmpty else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }

    public func string(forKey key: String) -> String? {
        guard let remoteConfig else { return nil }
        let value = remoteConfig[key].stringValue
        return value.isEmpty ? nil : value
    }

    public func bool(forKey key: String) -> Bool { remoteConfig?[key].boolValue ?? false }
    public func int(forKey key: String) -> Int { remoteConfig?[key].numberValue.intValue ?? 0 }
    public func double(forKey key: String) -> Double { remoteConfig?[key].numberValue.doubleValue ?? 0 }

    /// Seed in-app defaults so first launch has values before the first fetch returns.
    ///
    /// Safe to call before `A1SDK.configure(with:)`: the values are held and applied as soon
    /// as Remote Config is resolved, rather than being dropped or creating vendor state early.
    public func setDefaults(_ defaults: [String: NSObject]) {
        guard let remoteConfig else {
            pendingDefaults.merge(defaults) { _, new in new }
            return
        }
        remoteConfig.setDefaults(defaults)
    }
}
