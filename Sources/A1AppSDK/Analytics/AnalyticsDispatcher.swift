//
//  AnalyticsDispatcher.swift
//  A1AppSDK
//
//  Composite: one `log(_:)` call reaches every registered sink.
//
//  It also solves a boot-ordering problem. Modules in the foundation and identity phases
//  run before any analytics sink is configured, yet they have things worth reporting
//  (vendor init failures, auth errors). Those events are buffered here and replayed in
//  order once the first sink attaches, so early boot reporting is not silently lost.
//

import Foundation

public final class AnalyticsDispatcher: AnalyticsProvider {

    /// Buffer ceiling. Boot produces a handful of events; the cap only exists so an app
    /// that never registers a sink cannot grow this without bound.
    private static let maxBufferedEvents = 100

    /// A call made before the sinks existed, kept so it can be replayed verbatim.
    ///
    /// Errors are held alongside events rather than converted into one: a sink routes the
    /// two differently (Crashlytics non-fatal vs. analytics event), and replaying an error
    /// as an event would change what the dashboards receive.
    private enum PendingCall {
        case event(A1Event)
        case error(name: String, message: String, parameters: [String: Any]?)
    }

    private let lock = NSLock()
    private var sinks: [AnalyticsProvider] = []
    private var buffer: [PendingCall] = []
    private var lastKnownUserID: String?
    /// Boot is over. Until then every event is also kept so sinks that attach in a later
    /// phase still receive what happened before they existed.
    private var isSealed = false

    public var providerName: String { "AnalyticsDispatcher" }

    public init() {}

    // MARK: - Composition

    /// Add a sink. Any buffered boot events, and the current user id, are replayed into it.
    public func attach(_ sink: AnalyticsProvider) {
        lock.lock()
        guard !sinks.contains(where: { $0 === sink }) else { lock.unlock(); return }
        sinks.append(sink)
        let replay = buffer
        let userID = lastKnownUserID
        lock.unlock()

        if let userID, !userID.isEmpty {
            sink.identify(userID: userID)
        }
        for call in replay { deliver(call, to: sink) }
    }

    /// Attached sink names, for the apps' debug screens.
    public var attachedProviderNames: [String] {
        lock.lock(); defer { lock.unlock() }
        return sinks.map { $0.providerName }
    }

    // MARK: - AnalyticsProvider

    public func log(_ event: A1Event) {
        dispatch(.event(event))
    }

    /// Boot finished — release the replay buffer. Sinks attaching after this get live events only.
    public func sealBootBuffer() {
        lock.lock(); isSealed = true; buffer.removeAll(); lock.unlock()
    }

    public func setUserProperty(_ value: String?, for name: String) {
        for sink in currentSinks { sink.setUserProperty(value, for: name) }
    }

    public func identify(userID: String) {
        lock.lock()
        lastKnownUserID = userID
        let current = sinks
        lock.unlock()

        for sink in current { sink.identify(userID: userID) }
    }

    public func reportError(_ name: String, message: String, parameters: [String: Any]?) {
        // Buffered like an event: a module that fails during the bootstrap or foundation
        // phase reports before any sink exists, and that is exactly the report worth keeping.
        dispatch(.error(name: name, message: message, parameters: parameters))
    }

    // MARK: - Fan-out

    private func dispatch(_ call: PendingCall) {
        lock.lock()
        // Buffer during boot as well as delivering live: sinks boot in phase order, so a
        // sink attaching later must still receive what was reported before it existed.
        if !isSealed, buffer.count < Self.maxBufferedEvents { buffer.append(call) }
        let current = sinks
        lock.unlock()

        for sink in current { deliver(call, to: sink) }
    }

    private func deliver(_ call: PendingCall, to sink: AnalyticsProvider) {
        switch call {
        case .event(let event):
            sink.log(event)
        case .error(let name, let message, let parameters):
            sink.reportError(name, message: message, parameters: parameters)
        }
    }

    private var currentSinks: [AnalyticsProvider] {
        lock.lock(); defer { lock.unlock() }
        return sinks
    }
}
