//
//  IntercomAdapter.swift
//  A1AppSDK
//

import Foundation
import UIKit
import Intercom

public final class IntercomAdapter: A1Module, SupportProvider, A1LifecycleObserving {

    public var phase: A1BootPhase { .support }

    private var isConfigured = false
    private var identityToken: A1ObservationToken?
    private var analytics: AnalyticsProvider?
    /// Attributes the app wants attached to every user update.
    private var extraAttributes: [String: Any] = [:]

    public init() {}

    // MARK: - A1Module

    public func configure(context: A1ModuleContext) {
        guard let credentials = context.configuration.support else { return }
        analytics = context.analytics

        Intercom.setApiKey(credentials.apiKey, forAppId: credentials.appID)
        Intercom.setLauncherVisible(false)
        if context.configuration.isLoggingEnabled { Intercom.enableLogging() }

        login(userID: context.identity.userID)
        isConfigured = true

        // Anonymous on a first launch, upgraded to an identified user when auth resolves.
        identityToken = context.identity.observe { [weak self] userID in
            guard let self, self.isConfigured, !userID.isEmpty else { return }
            self.login(userID: userID)
        }
    }

    private func login(userID: String) {
        guard !userID.isEmpty else {
            Intercom.loginUnidentifiedUser()
            return
        }
        Intercom.loginUser(with: attributes(for: userID))
    }

    private func attributes(for userID: String) -> ICMUserAttributes {
        let user = ICMUserAttributes()
        user.userId = userID

        var custom: [String: Any] = [
            "App_Bundle_Identifer": Bundle.main.bundleIdentifier ?? "",
            "App_Name": Bundle.main.infoDictionary?[kCFBundleNameKey as String] as? String ?? "",
            "is_pro": A1SDK.shared.subscriptions?.isPro ?? false
        ]
        extraAttributes.forEach { custom[$0.key] = $0.value }
        user.customAttributes = custom
        return user
    }

    // MARK: - SupportProvider

    public func present(from viewController: UIViewController) {
        guard isConfigured else { return }
        Intercom.present()
    }

    public func updateUser(attributes newAttributes: [String: Any]) {
        guard isConfigured else { return }
        extraAttributes.merge(newAttributes) { _, latest in latest }
        Intercom.updateUser(with: attributes(for: A1SDK.shared.identity.userID))
    }

    public var unreadCount: Int {
        guard isConfigured else { return 0 }
        return Int(Intercom.unreadConversationCount())
    }

    // MARK: - A1LifecycleObserving

    public func didRegisterForRemoteNotifications(deviceToken: Data) {
        guard isConfigured else { return }
        Intercom.setDeviceToken(deviceToken) { [weak self] error in
            guard let error else { return }
            self?.analytics?.reportError("intercom_push_token_error",
                                         message: error.localizedDescription,
                                         parameters: nil)
        }
    }
}
