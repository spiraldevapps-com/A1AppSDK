//
//  TrackingAdapter.swift
//  A1AppSDK
//
//  App Tracking Transparency and the IDFA, as a module.
//
//  Boot only reads the current status — it never prompts. The prompt belongs to a moment
//  the app chooses, so it is behind `requestAuthorization(completion:)`.
//

import Foundation
import UIKit
import AppTrackingTransparency
import AdSupport

/// Tracking authorisation, without the vendor enum.
public enum A1TrackingStatus: String {
    case notDetermined
    case authorized
    case denied
    case restricted

    init(_ status: ATTrackingManager.AuthorizationStatus) {
        switch status {
        case .authorized:    self = .authorized
        case .denied:        self = .denied
        case .restricted:    self = .restricted
        case .notDetermined: self = .notDetermined
        @unknown default:    self = .notDetermined
        }
    }
}

public final class TrackingAdapter: A1Module, A1LifecycleObserving {

    public var phase: A1BootPhase { .foundation }

    /// What Apple hands back for the IDFA when tracking is not authorised. Passing it to a
    /// vendor as a device id is worse than passing nothing — every unauthorised device
    /// shares it — so it is filtered out rather than forwarded.
    private static let zeroIDFA = UUID(uuidString: "00000000-0000-0000-0000-000000000000")

    private let lock = NSLock()
    private var current: A1TrackingStatus = .notDetermined
    private var observers: [UUID: (A1TrackingStatus) -> Void] = [:]
    private var pending: [(A1TrackingStatus) -> Void] = []
    private var isPrompting = false
    /// False until the live ATT status has been read at least once.
    private var hasResolvedStatus = false
    private var isEnabled = true
    private var analytics: AnalyticsProvider?

    public init() {}

    // MARK: - A1Module

    public func configure(context: A1ModuleContext) {
        analytics = context.analytics
        isEnabled = context.configuration.isTrackingEnabled
        refresh()
    }

    // MARK: - State

    /// Safe before `configure(with:)`: if boot has not read the live value yet, it is read
    /// here. Reading the status never prompts — only `requestAuthorization` does — so this
    /// stays inert while still reporting the truth to a host that asks early.
    public var status: A1TrackingStatus {
        lock.lock()
        if hasResolvedStatus {
            defer { lock.unlock() }
            return current
        }
        lock.unlock()
        return refresh()
    }

    public var isAuthorized: Bool { status == .authorized }

    /// The IDFA, or nil whenever it may not be used.
    public var advertisingIdentifier: UUID? {
        guard isAuthorized else { return nil }
        let idfa = ASIdentifierManager.shared().advertisingIdentifier
        return idfa == Self.zeroIDFA ? nil : idfa
    }

    /// Observe the status. The handler fires immediately with the current value, on the
    /// main queue. Store the returned token — it cancels the subscription on deinit.
    @discardableResult
    public func observe(_ handler: @escaping (A1TrackingStatus) -> Void) -> A1ObservationToken {
        let key = UUID()
        let value: A1TrackingStatus = withLock { observers[key] = handler; return current }

        onMain { handler(value) }

        return A1ObservationToken { [weak self] in
            guard let self else { return }
            self.withLock { self.observers[key] = nil }
        }
    }

    // MARK: - Prompt

    /// Show the ATT prompt, or return the existing answer if there already is one.
    ///
    /// Safe from any thread and at any point in the launch sequence: the request is moved to
    /// the main thread, and if the app is not yet foreground-active it is held until it is.
    /// `requestTrackingAuthorization` silently does nothing outside the active state, so a
    /// request made too early would otherwise be lost with no callback at all.
    public func requestAuthorization(completion: @escaping (A1TrackingStatus) -> Void) {
        onMain { [weak self] in
            guard let self else { return }

            let status = self.refresh()
            guard self.isEnabled, status == .notDetermined else { completion(status); return }

            let isActive = UIApplication.shared.applicationState == .active
            self.lock.lock()
            self.pending.append(completion)
            let shouldPrompt = isActive && !self.isPrompting
            if shouldPrompt { self.isPrompting = true }
            self.lock.unlock()

            if shouldPrompt { self.prompt() }
        }
    }

    public func applicationDidBecomeActive(_ application: UIApplication) {
        let status = refresh()

        lock.lock()
        guard !pending.isEmpty, !isPrompting else { lock.unlock(); return }
        guard status == .notDetermined else {
            let waiting = pending
            pending.removeAll()
            lock.unlock()
            waiting.forEach { $0(status) }
            return
        }
        isPrompting = true
        lock.unlock()

        prompt()
    }

    private func prompt() {
        analytics?.log(A1Event("att_prompt_shown"))
        // Strong self: the callback fires exactly once, and the queued completions it has to
        // deliver live on this instance.
        ATTrackingManager.requestTrackingAuthorization { raw in
            let status = A1TrackingStatus(raw)
            // The vendor callback is not guaranteed to be on the main thread.
            DispatchQueue.main.async { self.finish(status) }
        }
    }

    private func finish(_ status: A1TrackingStatus) {
        analytics?.log(A1Event("att_prompt_result", parameters: ["status": status.rawValue]))
        publish(status)

        lock.lock()
        isPrompting = false
        let waiting = pending
        pending.removeAll()
        lock.unlock()

        waiting.forEach { $0(status) }
    }

    // MARK: - Publishing

    @discardableResult
    private func refresh() -> A1TrackingStatus {
        let status = A1TrackingStatus(ATTrackingManager.trackingAuthorizationStatus)
        lock.lock(); hasResolvedStatus = true; lock.unlock()
        publish(status)
        return status
    }

    private func publish(_ status: A1TrackingStatus) {
        lock.lock()
        guard status != current else { lock.unlock(); return }
        current = status
        let handlers = Array(observers.values)
        lock.unlock()

        guard !handlers.isEmpty else { return }
        onMain { handlers.forEach { $0(status) } }
    }

    /// NSLock is taken and released in one place, so a locked read cannot leak the lock.
    private func withLock<T>(_ work: () -> T) -> T {
        lock.lock(); defer { lock.unlock() }
        return work()
    }

    private func onMain(_ work: @escaping () -> Void) {
        if Thread.isMainThread { work() } else { DispatchQueue.main.async(execute: work) }
    }
}
