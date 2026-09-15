//
//  FirebaseAuthAdapter.swift
//  A1AppSDK
//
//  Establishes the anonymous user id every other vendor keys off.
//

import Foundation
import FirebaseCore
import FirebaseAuth

public final class FirebaseAuthAdapter: A1Module {

    public var phase: A1BootPhase { .identity }

    /// Mirrors the retry ceiling the apps already used.
    private static let maxRetries = 3
    private static let storageKey = "com.a1appsdk.identity.userID"

    private var retryCount = 0
    private weak var identity: A1Identity?
    private var analytics: AnalyticsProvider?

    /// Resolved in `configure(context:)`, never at construction.
    ///
    /// `Auth.auth()` raises `FIRAppNotConfigured` if Firebase has not been configured yet, and
    /// `A1SDK.standardModules()` builds every module up front — long before the bootstrap phase
    /// runs `FirebaseApp.configure()`. A module's initialiser must stay inert.
    private var auth: Auth?

    public init() {}

    public func configure(context: A1ModuleContext) {
        identity = context.identity
        analytics = context.analytics

        // Stage one, synchronous. A previously established id is published immediately so
        // modules booting in later phases are handed the real value on every launch after
        // the first. On a genuine first launch this is empty — which is correct.
        // Reading UserDefaults needs no vendor, so it happens even without Firebase.
        if let cached = UserDefaults.standard.string(forKey: Self.storageKey), !cached.isEmpty {
            context.identity.update(userID: cached)
        }

        // Phase order normally guarantees Firebase is up by now, but a host app may register
        // a subset of modules. Degrade quietly rather than raising FIRAppNotConfigured.
        guard FirebaseApp.app() != nil else {
            context.analytics.reportError("a1sdk_auth_no_firebase",
                                          message: "FirebaseApp is not configured; anonymous sign-in disabled",
                                          parameters: nil)
            return
        }

        let auth = Auth.auth()
        self.auth = auth

        // Firebase persists its own anonymous session, so prefer its view of the user.
        if let existing = auth.currentUser?.uid, !existing.isEmpty {
            publish(existing)
            return
        }

        // Stage two, asynchronous. Launch is never blocked on this.
        signInAnonymously()
    }

    private func signInAnonymously() {
        guard let auth else { return }

        auth.signInAnonymously { [weak self] result, error in
            guard let self else { return }

            if let uid = result?.user.uid, !uid.isEmpty {
                // Report the attempt this succeeded on, before resetting the counter.
                let attempt = self.retryCount
                self.retryCount = 0
                self.publish(uid)
                self.analytics?.log(A1Event("event_app_login_successfully",
                                            parameters: ["Attempt": "\(attempt)"]))
                return
            }

            let message = error?.localizedDescription ?? "Anonymous sign-in returned no user"
            self.analytics?.reportError("firebase_authentication_error", message: message, parameters: nil)
            self.retry()
        }
    }

    private func retry() {
        guard retryCount < Self.maxRetries else { return }
        retryCount += 1

        // Back off so a transient outage does not produce three instant failures.
        let delay = pow(2.0, Double(retryCount))
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            self?.signInAnonymously()
        }
    }

    private func publish(_ userID: String) {
        UserDefaults.standard.set(userID, forKey: Self.storageKey)
        identity?.update(userID: userID)
    }

    /// Current user id, or empty before sign-in resolves.
    ///
    /// Safe to call before `A1SDK.configure(with:)`: reads only the shared identity, never a vendor.
    public var userID: String { identity?.userID ?? "" }
}
