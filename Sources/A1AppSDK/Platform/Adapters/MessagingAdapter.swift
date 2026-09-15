//
//  MessagingAdapter.swift
//  A1AppSDK
//

import Foundation
import UIKit
import FirebaseCore
import FirebaseMessaging

/// Firebase Cloud Messaging token plumbing.
///
/// Only owns the token hand-off. Notification permission prompting and presentation stay
/// in the host app, which decides when and where to ask.
public final class MessagingAdapter: NSObject, A1Module, A1LifecycleObserving {

    public var phase: A1BootPhase { .notifications }

    /// Called when FCM issues or rotates a registration token.
    public var onTokenRefresh: ((String) -> Void)?

    private var analytics: AnalyticsProvider?

    /// Resolved in `configure(context:)`, never at construction.
    ///
    /// `Messaging.messaging()` raises `FIRAppNotConfigured` if Firebase has not been configured
    /// yet, and every module is constructed up front — long before the bootstrap phase runs
    /// `FirebaseApp.configure()`. A module's initialiser must stay inert.
    private var messaging: Messaging?

    /// An APNs token handed over before this module booted, applied once Messaging exists.
    private var pendingAPNSToken: Data?

    public override init() { super.init() }

    public func configure(context: A1ModuleContext) {
        analytics = context.analytics

        // Phase order normally guarantees Firebase is up by now, but a host app may register
        // a subset of modules. Degrade quietly rather than raising FIRAppNotConfigured.
        guard FirebaseApp.app() != nil else {
            context.analytics.reportError("a1sdk_messaging_no_firebase",
                                          message: "FirebaseApp is not configured; messaging disabled",
                                          parameters: nil)
            return
        }

        let messaging = Messaging.messaging()
        self.messaging = messaging
        messaging.delegate = self

        if let pendingAPNSToken {
            messaging.apnsToken = pendingAPNSToken
            self.pendingAPNSToken = nil
        }
    }

    public func didRegisterForRemoteNotifications(deviceToken: Data) {
        // The AppDelegate callback can land before this module's phase runs; hold the token
        // instead of touching the vendor early.
        guard let messaging else {
            pendingAPNSToken = deviceToken
            return
        }
        messaging.apnsToken = deviceToken
    }

    /// Current FCM token, if one has been issued.
    ///
    /// Safe to call before `A1SDK.configure(with:)` — completes with `nil` rather than crashing.
    public func currentToken(completion: @escaping (String?) -> Void) {
        guard let messaging else {
            completion(nil)
            return
        }
        messaging.token { token, _ in completion(token) }
    }
}

// MARK: - MessagingDelegate

extension MessagingAdapter: MessagingDelegate {
    public func messaging(_ messaging: Messaging, didReceiveRegistrationToken fcmToken: String?) {
        guard let fcmToken else { return }
        onTokenRefresh?(fcmToken)
    }
}
