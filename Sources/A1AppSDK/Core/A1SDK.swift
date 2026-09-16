//
//  A1SDK.swift
//  A1AppSDK
//
//  The single entry point. A host app registers the frameworks it wants, calls
//  `configure(with:)` once, and forwards a handful of UIApplicationDelegate events.
//  Everything else — ordering, identity propagation, vendor setup — happens in here.
//
//  ORDERING INVARIANT — read this before adding a module.
//
//  The boot phase orders `configure(context:)` calls. It does NOT order *construction*.
//  Every module is built when the host app calls `register(_:)`, which is before
//  `configure(with:)` has run and therefore before `FirebaseApp.configure()` and every
//  other vendor bootstrap. A module whose `init` — or whose stored-property initialiser —
//  touches a vendor SDK runs that vendor call at registration time and will crash or
//  mis-initialise. See `A1Module` for the full contract.
//

import Foundation
import UIKit

public final class A1SDK {

    public static let shared = A1SDK()

    /// Shared user identity. Modules observe this; the app publishes to it via
    /// whichever auth module it registered.
    public let identity = A1Identity()

    private var _configuration = A1Configuration()
    private var _isConfigured = false

    /// Configuration supplied at `configure(with:)`. Reading before boot yields defaults.
    public var configuration: A1Configuration {
        lock.lock(); defer { lock.unlock() }
        return _configuration
    }

    /// `true` once `configure(with:)` has run.
    public var isConfigured: Bool {
        lock.lock(); defer { lock.unlock() }
        return _isConfigured
    }

    private var modules: [A1Module] = []
    private let dispatcher = AnalyticsDispatcher()
    private let lock = NSLock()
    /// Retained deliberately: A1ObservationToken cancels itself on deinit, so discarding
    /// this would tear the subscription down the instant it was created.
    private var identityToken: A1ObservationToken?
    /// Type-keyed resolution cache. `module(_:)` sits on hot paths — `isReachable` consults it on
    /// every ad check — and the uncached form scanned and allocated on each call.
    /// Invalidated on every registration, since a new module can satisfy a previously-missed type.
    private var resolutionCache: [ObjectIdentifier: AnyObject] = [:]
    /// Lifecycle observers in phase order, computed once at boot instead of re-sorted per event.
    private var orderedLifecycleObservers: [A1LifecycleObserving] = []

    private init() {}

    // MARK: - Registration

    /// Register a framework.
    ///
    /// Call before `configure(with:)`. Registering the same module identifier twice is
    /// ignored, so a module registered by both the app and a default set boots once.
    ///
    /// The module is *constructed* by the caller, i.e. now — its `init` must be inert
    /// (see `A1Module`). Vendor work belongs in `configure(context:)`, which this
    /// orchestrator calls in phase order.
    ///
    /// Anything conforming to `A1Module` plus a provider protocol becomes that provider —
    /// which is also how a test injects a mock:
    /// ```swift
    /// A1SDK.shared.register(MockSubscriptionProvider())
    /// ```
    public func register(_ module: A1Module) {
        lock.lock()
        guard !modules.contains(where: { $0.moduleIdentifier == module.moduleIdentifier }) else {
            lock.unlock()
            log("skipped duplicate module \(module.moduleIdentifier)")
            return
        }
        modules.append(module)
        // A late module can satisfy a type that previously resolved to nil, so the whole
        // cache goes — including any entry this module now shadows.
        resolutionCache.removeAll(keepingCapacity: true)
        rebuildLifecycleObserversLocked()
        let bootAlreadyRan = _isConfigured
        lock.unlock()

        // Registered after boot: configure it now so it is never left uninitialised,
        // then attach it so it receives anything still buffered.
        if bootAlreadyRan {
            let context = makeContext()
            // Same main-thread guarantee the boot path gives, so a late module cannot end up
            // running vendor setup on a background queue.
            onMain {
                module.configure(context: context)
                self.attachIfAnalyticsSink(module)
            }
        }
    }

    /// Register several modules in one call. Order here is irrelevant — boot order comes
    /// from each module's `phase`.
    public func register(_ modules: [A1Module]) {
        modules.forEach(register)
    }

    // MARK: - Boot

    /// Boot every registered module, in phase order, on the main thread.
    ///
    /// Idempotent: calling twice is a no-op, so an app that configures from both
    /// `didFinishLaunching` and a scene delegate cannot double-initialise a vendor.
    ///
    /// Called off the main thread, this hops to it and blocks, because `A1Module`
    /// guarantees modules that `configure(context:)` runs on the main thread and several
    /// vendors (AdMob, Meta, ATT) require it.
    public func configure(with configuration: A1Configuration) {
        guard Thread.isMainThread else {
            DispatchQueue.main.sync { self.configure(with: configuration) }
            return
        }

        lock.lock()
        guard !_isConfigured else {
            lock.unlock()
            log("configure(with:) called more than once — ignoring")
            return
        }
        _isConfigured = true
        _configuration = configuration
        // enumerated() keeps registration order within a phase — Swift's sort is not stable,
        // so without this the three .analytics modules boot in undefined order.
        let ordered = modules.enumerated()
            .sorted { ($0.element.phase, $0.offset) < ($1.element.phase, $1.offset) }
            .map(\.element)
        lock.unlock()

        dispatcher.setNameOverrides(configuration.eventNameOverrides)
        dispatcher.setParameterProvider(configuration.eventParameterProvider)
        let context = makeContext()

        let bootStart = CFAbsoluteTimeGetCurrent()
        var moduleDurations: [(String, Int64)] = []
        moduleDurations.reserveCapacity(ordered.count)

        for module in ordered {
            log("configuring \(module.moduleIdentifier) [phase \(module.phase.rawValue)]")
            let started = CFAbsoluteTimeGetCurrent()
            module.configure(context: context)
            moduleDurations.append((module.moduleIdentifier,
                                    Int64((CFAbsoluteTimeGetCurrent() - started) * 1000)))
            // Attach only after the sink has initialised its vendor, so replayed boot
            // events land in a ready sink instead of being silently dropped.
            attachIfAnalyticsSink(module)
        }

        // Keep every identity-aware sink in step with sign-in, which resolves later.
        // Assigned before observing: `observe` fires the handler synchronously with the
        // current value, and a token dropped on the floor cancels itself in deinit.
        let token = identity.observe { [weak self] userID in
            guard let self, !userID.isEmpty else { return }
            self.dispatcher.identify(userID: userID)
        }
        lock.lock()
        identityToken = token
        lock.unlock()

        dispatcher.sealBootBuffer()
        // The legacy EventManager emitted this on every launch for every app; keep parity.
        dispatcher.log(.event_app_first_open)

        // Launch timing, per module and in total, on the trace PerformanceAdapter opened at
        // phase 51. Modules that booted before it (FirebaseCore) are still recorded as metrics.
        if let performance = module(PerformanceAdapter.self) {
            for (identifier, ms) in moduleDurations { performance.recordBootModule(identifier, milliseconds: ms) }
            performance.finishBootTrace(totalMilliseconds: Int64((CFAbsoluteTimeGetCurrent() - bootStart) * 1000))
        }
        log("boot complete — \(ordered.count) module(s)")
    }

    private func makeContext() -> A1ModuleContext {
        A1ModuleContext(configuration: configuration, identity: identity, analytics: dispatcher)
    }

    private func attachIfAnalyticsSink(_ module: A1Module) {
        guard let sink = module as? AnalyticsProvider, sink !== dispatcher else { return }
        dispatcher.attach(sink)
    }

    /// Run `work` on the main thread, inline when already there. Never called with `lock` held.
    private func onMain(_ work: () -> Void) {
        if Thread.isMainThread {
            work()
        } else {
            DispatchQueue.main.sync(execute: work)
        }
    }

    /// Phase-ordered, registration-order-stable within a phase — the same rule boot uses.
    /// Caller must hold `lock`.
    private func rebuildLifecycleObserversLocked() {
        orderedLifecycleObservers = modules.enumerated()
            .sorted { ($0.element.phase, $0.offset) < ($1.element.phase, $1.offset) }
            .compactMap { $0.element as? A1LifecycleObserving }
    }

    // MARK: - Providers
    //
    // Every accessor below is safe to call before `configure(with:)`: they only look through
    // what is already registered and return nil when nothing matches. None of them constructs
    // or touches a vendor.

    /// The subscription engine, if one was registered.
    public var subscriptions: SubscriptionProvider? { resolve() }

    /// The ad engine, if one was registered.
    public var ads: AdsProvider? { resolve() }

    /// The analytics fan-out. Never nil — with no sinks attached it buffers, then discards.
    public var analytics: AnalyticsDispatcher { dispatcher }

    /// Customer messaging, if one was registered.
    public var support: SupportProvider? { resolve() }

    /// Fetch a registered module by type, for anything the provider protocols do not cover.
    ///
    /// Returns nil before the module is registered. Safe at any point in the app's life,
    /// including before boot — but note the module it hands back may not be configured yet,
    /// so a module's own accessors must degrade rather than crash.
    public func module<T>(_ type: T.Type = T.self) -> T? { resolve() }

    private func resolve<T>() -> T? {
        let key = ObjectIdentifier(T.self)
        lock.lock(); defer { lock.unlock() }

        if let hit = resolutionCache[key] { return hit as? T }
        // first(where:) rather than compactMap().first — no intermediate array.
        guard let found = modules.first(where: { $0 is T }) else { return nil }
        resolutionCache[key] = found
        return found as? T
    }

    // MARK: - UIApplicationDelegate forwarding

    /// Phase-ordered so Meta's SDK sees didFinishLaunching before later modules, whatever order
    /// the app registered things in. Built at registration, not rebuilt per event.
    private var lifecycleObservers: [A1LifecycleObserving] {
        lock.lock(); defer { lock.unlock() }
        return orderedLifecycleObservers
    }

    public func application(_ application: UIApplication,
                            didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) {
        lifecycleObservers.forEach {
            $0.applicationDidFinishLaunching(application, launchOptions: launchOptions)
        }
    }

    public func applicationDidBecomeActive(_ application: UIApplication) {
        lifecycleObservers.forEach { $0.applicationDidBecomeActive(application) }
    }

    /// Returns `true` if any module handled the URL.
    @discardableResult
    public func application(_ application: UIApplication,
                            open url: URL,
                            options: [UIApplication.OpenURLOptionsKey: Any] = [:]) -> Bool {
        // reduce, not first-match: every module must see the URL even once one has handled it.
        lifecycleObservers.reduce(false) { handled, observer in
            observer.application(application, open: url, options: options) || handled
        }
    }

    public func didRegisterForRemoteNotifications(deviceToken: Data) {
        lifecycleObservers.forEach { $0.didRegisterForRemoteNotifications(deviceToken: deviceToken) }
    }

    // MARK: - Diagnostics

    /// Registered modules in boot order, for debug screens.
    public var registeredModules: [(identifier: String, phase: Int)] {
        lock.lock(); defer { lock.unlock() }
        // Mirrors the boot sort exactly, ties included, so a debug screen shows real boot order.
        return modules.enumerated()
            .sorted { ($0.element.phase, $0.offset) < ($1.element.phase, $1.offset) }
            .map { ($0.element.moduleIdentifier, $0.element.phase.rawValue) }
    }

    private func log(_ message: String) {
        guard configuration.isLoggingEnabled else { return }
        print("[A1SDK] \(message)")
    }
}
