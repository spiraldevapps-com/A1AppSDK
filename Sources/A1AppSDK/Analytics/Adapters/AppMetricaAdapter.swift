//
//  AppMetricaAdapter.swift
//  A1AppSDK
//

import Foundation
import AppMetricaCore
import AppMetricaCrashes

/// AppMetrica event sink and non-fatal error reporter.
public final class AppMetricaAdapter: A1Module, AnalyticsProvider {

    public var phase: A1BootPhase { .analytics }
    public var providerName: String { "AppMetrica" }

    private var isActive = false
    private var identityToken: A1ObservationToken?

    public init() {}

    public func configure(context: A1ModuleContext) {
        // Preserves existing behaviour exactly: no key means AppMetrica is skipped entirely.
        guard let apiKey = context.configuration.appMetricaAPIKey, !apiKey.isEmpty else { return }

        // The previous implementation force-unwrapped this initialiser, which crashes the app
        // on a malformed key. Failing soft and reporting is strictly safer.
        guard let configuration = AppMetricaConfiguration(apiKey: apiKey) else {
            context.analytics.reportError("a1sdk_appmetrica_config_invalid",
                                          message: "AppMetricaConfiguration returned nil for the supplied key",
                                          parameters: nil)
            return
        }

        // Empty on a first launch — expected. `identify(userID:)` corrects it when auth resolves.
        configuration.userProfileID = context.identity.userID
        configuration.areLogsEnabled = context.configuration.isLoggingEnabled

        AppMetrica.activate(with: configuration)
        isActive = true

        identityToken = context.identity.observe { [weak self] userID in
            self?.identify(userID: userID)
        }
    }

    public func log(_ event: A1Event) {
        guard isActive else { return }
        AppMetrica.reportEvent(name: event.name, parameters: event.parameters)
    }

    public func identify(userID: String) {
        guard isActive, !userID.isEmpty else { return }
        AppMetrica.userProfileID = userID
    }

    public func reportError(_ name: String, message: String, parameters: [String: Any]?) {
        guard isActive else { return }
        let error = AppMetricaError(identifier: name,
                                    message: message,
                                    parameters: parameters,
                                    backtrace: Thread.callStackReturnAddresses,
                                    underlyingError: nil)
        AppMetricaCrashes.crashes().report(error: error, onFailure: nil)
    }
}
