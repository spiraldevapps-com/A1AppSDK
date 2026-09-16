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

    /// A call made before the sinks existed, kept raw so it can be replayed. The rename
    /// table and parameter provider are applied at delivery, not here: both are installed
    /// by `configure(with:)`, and anything logged before that must still get them.
    ///
    /// Errors are held alongside events rather than converted into one: a sink routes the
    /// two differently (Crashlytics non-fatal vs. analytics event), and replaying an error
    /// as an event would change what the dashboards receive.
    private enum PendingCall {
        case event(A1Event)
        case error(name: String, message: String, parameters: [String: Any]?)
        /// Buffered too: modules in early phases (storefront at .identity, attribution at
        /// .foundation) set properties before any sink exists, and a property that never
        /// reaches Firebase is a silent hole in every user-scoped report.
        case userProperty(name: String, value: String?)
    }

    private let lock = NSLock()
    private var sinks: [AnalyticsProvider] = []
    private var buffer: [PendingCall] = []
    private var lastKnownUserID: String?
    /// Per-app rename table, set once at boot. Empty for apps using the shared vocabulary.
    private var nameOverrides: [String: String] = [:]
    /// App-supplied parameters merged into every event and error (e.g. `isPro`).
    private var parameterProvider: (() -> [String: Any])?
    /// Boot is over. Until then every event is also kept so sinks that attach in a later
    /// phase still receive what happened before they existed.
    private var isSealed = false

    public var providerName: String { "AnalyticsDispatcher" }

    public init() {}

    /// Install the app's rename table. Called by `A1SDK.configure(with:)` before any module boots.
    public func setNameOverrides(_ overrides: [String: String]) {
        lock.lock(); nameOverrides = overrides; lock.unlock()
    }

    /// Install the app's global-parameter source. Set once at boot.
    public func setParameterProvider(_ provider: (() -> [String: Any])?) {
        lock.lock(); parameterProvider = provider; lock.unlock()
    }

    private func resolved(_ name: String) -> String {
        lock.lock(); defer { lock.unlock() }
        return nameOverrides[name] ?? name
    }

    /// Global parameters merged underneath the call's own — specific values win on collision.
    private func enriched(_ parameters: [String: Any]?) -> [String: Any]? {
        lock.lock(); let provider = parameterProvider; lock.unlock()
        guard let provider else { return parameters }
        let merged = provider().merging(parameters ?? [:]) { _, specific in specific }
        return merged.isEmpty ? nil : merged
    }

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
        for call in replay { deliver(resolve(call), to: sink) }
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
        dispatch(.userProperty(name: name, value: value))
    }

    public func identify(userID: String) {
        lock.lock()
        lastKnownUserID = userID
        let current = sinks
        lock.unlock()

        for sink in current { sink.identify(userID: userID) }
    }

    public func reportError(_ rawName: String, message: String, parameters: [String: Any]?) {
        // Buffered like an event: a module that fails during the bootstrap or foundation
        // phase reports before any sink exists, and that is exactly the report worth keeping.
        dispatch(.error(name: rawName, message: message, parameters: parameters))
    }

    // MARK: - Fan-out

    private func dispatch(_ call: PendingCall) {
        lock.lock()
        // Buffer during boot as well as delivering live: sinks boot in phase order, so a
        // sink attaching later must still receive what was reported before it existed.
        if !isSealed, buffer.count < Self.maxBufferedEvents { buffer.append(call) }
        let current = sinks
        lock.unlock()

        // Resolved once per call, not once per sink: the parameter provider is app code.
        let live = resolve(call)
        for sink in current { deliver(live, to: sink) }
    }

    /// Apply the rename table and the global parameters. Done at delivery time so a call
    /// buffered before `configure(with:)` installed them still gets both.
    private func resolve(_ call: PendingCall) -> PendingCall {
        switch call {
        case .event(let event):
            return .event(A1Event(resolved(event.name), parameters: enriched(event.parameters)))
        case .error(let name, let message, let parameters):
            return .error(name: resolved(name), message: message, parameters: enriched(parameters))
        case .userProperty:
            return call
        }
    }

    private func deliver(_ call: PendingCall, to sink: AnalyticsProvider) {
        switch call {
        case .event(let event):
            sink.log(event)
        case .error(let name, let message, let parameters):
            sink.reportError(name, message: message, parameters: parameters)
        case .userProperty(let name, let value):
            sink.setUserProperty(value, for: name)
        }
    }

    private var currentSinks: [AnalyticsProvider] {
        lock.lock(); defer { lock.unlock() }
        return sinks
    }
}
