//
//  FirebaseCoreAdapter.swift
//  A1AppSDK
//

import Foundation
import FirebaseCore

/// `FirebaseApp.configure()`.
///
/// Sits in `.bootstrap`, ahead of every other phase, because Analytics, Auth, Remote Config,
/// Crashlytics and Messaging all fail if Firebase is not already configured.
public final class FirebaseCoreAdapter: A1Module {

    public var phase: A1BootPhase { .bootstrap }

    public private(set) var isConfigured = false

    public init() {}

    public func configure(context: A1ModuleContext) {
        // Guard against a host app that still calls FirebaseApp.configure() itself —
        // configuring twice raises an exception.
        guard FirebaseApp.app() == nil else {
            isConfigured = true
            return
        }

        FirebaseApp.configure()
        isConfigured = FirebaseApp.app() != nil

        if !isConfigured {
            context.analytics.reportError(.firebase_configure_failed,
                                          message: "FirebaseApp.app() was nil after configure()",
                                          parameters: nil)
        }
    }
}
