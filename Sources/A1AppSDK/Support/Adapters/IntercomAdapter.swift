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
    private var entitlementToken: A1ObservationToken?
    /// The pro flag last sent to the vendor, so an entitlement broadcast that changes
    /// nothing does not push the same attributes again.
    private var lastSentIsPro: Bool?
    /// The APNs token last handed to the vendor, so the two entry points (lifecycle hook
    /// and `registerForPush`) cannot register the same token twice.
    private var lastDeviceToken: Data?
    /// The id the vendor currently holds, so an identity broadcast of the same value does
    /// not log the user in a second time.
    private var loggedInUserID = ""
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
        Intercom.setInAppMessagesVisible(credentials.isInAppMessagingEnabled)
        if context.configuration.isLoggingEnabled { Intercom.enableLogging() }

        login(userID: context.identity.userID)
        isConfigured = true

        // Anonymous on a first launch, upgraded to an identified user when auth resolves.
        identityToken = context.identity.observe { [weak self] userID in
            guard let self, self.isConfigured, !userID.isEmpty, userID != self.loggedInUserID else { return }
            self.login(userID: userID)
        }

        // `is_pro` goes out with the login and must follow the entitlement afterwards: a
        // purchase, restore or lapse would otherwise show the old value until relaunch.
        entitlementToken = A1SDK.shared.subscriptions?.observeEntitlement { [weak self] isPro in
            guard let self, !self.loggedInUserID.isEmpty, isPro != self.lastSentIsPro else { return }
            Intercom.updateUser(with: self.attributes(for: self.loggedInUserID))
        }
    }

    private func login(userID: String) {
        loggedInUserID = userID
        guard !userID.isEmpty else {
            Intercom.loginUnidentifiedUser()
            return
        }
        Intercom.loginUser(with: attributes(for: userID))
    }

    private func attributes(for userID: String) -> ICMUserAttributes {
        let user = ICMUserAttributes()
        user.userId = userID

        let isPro = A1SDK.shared.subscriptions?.isPro ?? false
        lastSentIsPro = isPro
        var custom: [String: Any] = [
            "App_Bundle_Identifer": Bundle.main.bundleIdentifier ?? "",
            "App_Name": Bundle.main.infoDictionary?[kCFBundleNameKey as String] as? String ?? "",
            "is_pro": isPro
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
        // Before identity resolves there is no user to update, and sending an empty userId
        // earns a vendor validation warning. The merged extras go out with the login that
        // follows identity resolution (`attributes(for:)` reads them), so nothing is lost.
        guard !loggedInUserID.isEmpty else { return }
        Intercom.updateUser(with: attributes(for: loggedInUserID))
    }

    public var unreadCount: Int {
        guard isConfigured else { return 0 }
        return Int(Intercom.unreadConversationCount())
    }

    /// Same path as the lifecycle hook, so an app may hand the token to either.
    public func registerForPush(deviceToken: Data) {
        didRegisterForRemoteNotifications(deviceToken: deviceToken)
    }

    // MARK: - A1LifecycleObserving

    public func didRegisterForRemoteNotifications(deviceToken: Data) {
        guard isConfigured, deviceToken != lastDeviceToken else { return }
        lastDeviceToken = deviceToken
        Intercom.setDeviceToken(deviceToken) { [weak self] error in
            guard let self, let error else { return }
            // Let the same token be retried on the next registration.
            self.lastDeviceToken = nil
            self.analytics?.reportError(.intercom_push_token_error,
                                        message: error.localizedDescription,
                                        parameters: nil)
        }
    }
}
