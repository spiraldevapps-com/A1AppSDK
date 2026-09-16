//
//  RatingAdapter.swift
//  A1AppSDK
//
//  The App Store review prompt, in one place.
//
//  Apple silently caps prompts at roughly three per 365 days and never tells you whether
//  one was shown, so the policy here is not about limiting the user — it is about not
//  spending those three on a moment the user is unlikely to answer well.
//
//  Call site:
//  ```swift
//  A1SDK.shared.module(RatingAdapter.self)?.requestReviewIfAppropriate(reason: "export_completed")
//  ```
//

import Foundation
import UIKit
import StoreKit

public final class RatingAdapter: A1Module {

    /// Thresholds a prompt must clear. Tune per app; every value has a working default.
    public struct Policy {
        /// Launches before the first prompt is allowed.
        public var minimumSessions: Int = 3
        /// Positive moments (`noteSignificantEvent()`) required since the last prompt.
        public var minimumSignificantEvents: Int = 2
        /// Gap between two requests.
        public var minimumInterval: TimeInterval = 60 * 60 * 24 * 60
        /// Quiet period after a paywall or full-screen ad is dismissed. A prompt stacked on
        /// a dismissal reads as part of it, and gets answered accordingly.
        public var quietPeriod: TimeInterval = 300

        public init() {}
    }

    public var phase: A1BootPhase { .support }

    private enum Key {
        static let sessions = "com.a1appsdk.rating.sessionCount"
        static let events = "com.a1appsdk.rating.significantEvents"
        static let lastRequest = "com.a1appsdk.rating.lastRequest"
    }

    /// Computed, not a stored property: `UserDefaults.standard` faults the domain in from
    /// disk on first touch, and construction of a module must stay free of that.
    private var defaults: UserDefaults { .standard }
    private let lock = NSLock()
    private var storedPolicy = Policy()
    /// In memory only: a quiet period measured in minutes is over by the next launch.
    private var lastInterruption = Date.distantPast
    private var analytics: AnalyticsProvider?

    public init(policy: Policy = Policy()) { storedPolicy = policy }

    /// Current thresholds. Read-modify-write to tune one value:
    /// `adapter.policy.minimumSessions = 5`. Survives boot: `configure` layers any
    /// `A1Configuration.custom` keys on top of it rather than replacing it.
    public var policy: Policy {
        get { lock.lock(); defer { lock.unlock() }; return storedPolicy }
        set { lock.lock(); storedPolicy = newValue; lock.unlock() }
    }

    // MARK: - A1Module

    public func configure(context: A1ModuleContext) {
        analytics = context.analytics

        var policy = self.policy
        // NSNumber bridging so an app may pass either an Int or a Double.
        func value(_ key: String) -> Double? {
            (context.configuration.custom[key] as? NSNumber)?.doubleValue
        }
        if let v = value("ratingMinimumSessions") { policy.minimumSessions = Int(v) }
        if let v = value("ratingMinimumSignificantEvents") { policy.minimumSignificantEvents = Int(v) }
        if let v = value("ratingMinimumInterval") { policy.minimumInterval = v }
        if let v = value("ratingQuietPeriod") { policy.quietPeriod = v }

        lock.lock()
        storedPolicy = policy
        // configure() runs once per launch, so this is the session count.
        defaults.set(defaults.integer(forKey: Key.sessions) + 1, forKey: Key.sessions)
        lock.unlock()
    }

    // MARK: - Public API

    /// Whether every threshold is currently met.
    public var canRequestReview: Bool {
        lock.lock(); defer { lock.unlock() }
        return isEligible
    }

    /// Record a moment worth being asked about — a document exported, a scan finished.
    public func noteSignificantEvent() {
        lock.lock()
        defaults.set(defaults.integer(forKey: Key.events) + 1, forKey: Key.events)
        lock.unlock()
    }

    /// Record a paywall or full-screen ad dismissal, opening the quiet period.
    public func noteInterruption() {
        lock.lock()
        lastInterruption = Date()
        lock.unlock()
    }

    /// Ask for a review if the policy allows it. Safe to call from anywhere, as often as you like.
    /// Prompt only if the pacing policy allows. For prompts the APP initiates.
    public func requestReviewIfAppropriate(reason: String) {
        request(reason: reason, enforcingPolicy: true)
    }

    /// Prompt now, skipping the pacing policy. For requests the USER initiates.
    ///
    /// The policy exists to stop the app spending Apple's ~3-prompts-a-year budget on
    /// moments the user did not ask for. When the user has just tapped a star rating, the
    /// request is theirs — gating it makes the tap do nothing. Apple still applies its own
    /// rate limit, so this cannot over-prompt.
    public func requestReview(reason: String) {
        request(reason: reason, enforcingPolicy: false)
    }

    private func request(reason: String, enforcingPolicy: Bool) {
        guard Thread.isMainThread else {
            DispatchQueue.main.async { [weak self] in self?.request(reason: reason, enforcingPolicy: enforcingPolicy) }
            return
        }

        lock.lock()
        if enforcingPolicy, !isEligible { lock.unlock(); return }
        let sessions = defaults.integer(forKey: Key.sessions)
        lock.unlock()

        // No foreground scene means nothing could be presented; leave the counters intact
        // so the next opportunity still qualifies.
        guard let scene = UIApplication.shared.connectedScenes.lazy
            .compactMap({ $0 as? UIWindowScene })
            .first(where: { $0.activationState == .foregroundActive }) else { return }

        lock.lock()
        defaults.set(Date().timeIntervalSince1970, forKey: Key.lastRequest)
        defaults.set(0, forKey: Key.events)
        lock.unlock()

        SKStoreReviewController.requestReview(in: scene)
        analytics?.log(A1Event(.rating_prompt_requested,
                               parameters: ["reason": reason,
                                            "sessions": "\(sessions)",
                                            "policy_enforced": "\(enforcingPolicy)"]))
    }

    // MARK: - Policy evaluation

    /// Caller holds `lock`.
    private var isEligible: Bool {
        guard defaults.integer(forKey: Key.sessions) >= storedPolicy.minimumSessions,
              defaults.integer(forKey: Key.events) >= storedPolicy.minimumSignificantEvents,
              Date().timeIntervalSince(lastInterruption) >= storedPolicy.quietPeriod else { return false }

        let last = defaults.double(forKey: Key.lastRequest)
        return last == 0 || Date().timeIntervalSince1970 - last >= storedPolicy.minimumInterval
    }
}
