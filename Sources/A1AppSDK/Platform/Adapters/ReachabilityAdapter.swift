//
//  ReachabilityAdapter.swift
//  A1AppSDK
//
//  One long-lived NWPathMonitor for the whole process, replacing the hand-written
//  reachability helpers in the host apps and the per-call reachability object the ads
//  module rebuilt on every single ad check.
//

import Foundation
import Network

public final class ReachabilityAdapter: A1Module {

    public var phase: A1BootPhase { .foundation }

    // Constructed in configure(), never in a stored-property initialiser: allocating an
    // NWPathMonitor already stands up a system path object, and a module the host registers
    // but never configures must cost nothing.
    private var monitor: NWPathMonitor?
    private let queue = DispatchQueue(label: "com.a1appsdk.reachability")
    private let lock = NSLock()

    // Seeded optimistically. The first path update lands a few milliseconds after start,
    // and a false "offline" in that window silently suppresses a launch-time ad, whereas a
    // false "online" costs one request the vendor SDKs already fail gracefully.
    private var connected = true
    private var expensive = false
    private var constrained = false

    private var observers: [UUID: (Bool) -> Void] = [:]
    private var isMonitoring = false
    private var analytics: AnalyticsProvider?
    private var isLoggingEnabled = false

    public init() {}

    deinit { monitor?.cancel() }

    // MARK: - A1Module

    public func configure(context: A1ModuleContext) {
        analytics = context.analytics
        isLoggingEnabled = context.configuration.isNetworkStatusLoggingEnabled

        lock.lock()
        guard !isMonitoring else { lock.unlock(); return }
        isMonitoring = true
        lock.unlock()

        let monitor = NWPathMonitor()
        self.monitor = monitor
        monitor.pathUpdateHandler = { [weak self] path in self?.apply(path) }
        monitor.start(queue: queue)
    }

    // MARK: - State

    /// Cheap synchronous read — a cached value, not a fresh probe.
    public var isConnected: Bool { lock.lock(); defer { lock.unlock() }; return connected }

    /// Cellular, personal hotspot, or another interface the user pays for.
    public var isExpensive: Bool { lock.lock(); defer { lock.unlock() }; return expensive }

    /// Low Data Mode is on for the current interface.
    public var isConstrained: Bool { lock.lock(); defer { lock.unlock() }; return constrained }

    // MARK: - Observation

    /// Observe connectivity. Fires immediately with the current value, then on every flip.
    ///
    /// The returned token cancels itself on deinit — store it in a property or the
    /// subscription dies at the end of the calling scope.
    @discardableResult
    public func observe(_ handler: @escaping (Bool) -> Void) -> A1ObservationToken {
        let key = UUID()

        lock.lock()
        observers[key] = handler
        let current = connected
        lock.unlock()

        deliver([handler], value: current)

        return A1ObservationToken { [weak self] in
            guard let self else { return }
            self.lock.lock()
            self.observers[key] = nil
            self.lock.unlock()
        }
    }

    // MARK: - Path handling

    private func apply(_ path: NWPath) {
        let isUp = path.status == .satisfied
        let isExpensive = path.isExpensive

        lock.lock()
        expensive = isExpensive
        constrained = path.isConstrained
        // Observers hear about connectivity only — interface churn on a live connection
        // (Wi-Fi to cellular) fires this handler repeatedly and is not a state change.
        guard isUp != connected else { lock.unlock(); return }
        connected = isUp
        let handlers = Array(observers.values)
        lock.unlock()

        if isLoggingEnabled {
            analytics?.log(A1Event(.network_status_changed,
                                   parameters: ["connected": isUp ? "yes" : "no",
                                                "expensive": isExpensive ? "yes" : "no"]))
        }

        deliver(handlers, value: isUp)
    }

    private func deliver(_ handlers: [(Bool) -> Void], value: Bool) {
        guard !handlers.isEmpty else { return }
        if Thread.isMainThread {
            handlers.forEach { $0(value) }
        } else {
            DispatchQueue.main.async { handlers.forEach { $0(value) } }
        }
    }
}
