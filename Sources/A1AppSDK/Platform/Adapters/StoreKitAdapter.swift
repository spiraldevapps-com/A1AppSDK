//
//  StoreKitAdapter.swift
//  A1AppSDK
//
//  StoreKit 2 as an entitlement source. Replaces the hand-written StorekitManager each
//  app carried — same storefront analytics, plus the transaction listener none of those
//  versions had. Purchases and paywalls stay with the subscription vendor; this file only
//  reads what Apple already considers owned.
//

import Foundation
import UIKit
import StoreKit

public final class StoreKitAdapter: A1Module, A1LifecycleObserving, @unchecked Sendable {

    public var phase: A1BootPhase { .identity }

    private static let storefrontProperty = "store"
    private static let storefrontRetries = 3

    // MARK: - State

    private let lock = NSLock()
    private var entitled = false
    private var storefront: String?
    private var observers: [UUID: (Bool) -> Void] = [:]
    private var allowedProductIDs: Set<String> = []

    private var analytics: AnalyticsProvider?
    private var updatesTask: Task<Void, Never>?

    public init() {}

    deinit { updatesTask?.cancel() }

    // MARK: - A1Module

    public func configure(context: A1ModuleContext) {
        analytics = context.analytics
        // Empty means any active entitlement counts, which is what the default set already says.
        let ids = Set(context.configuration.entitlementProductIDs)
        if !ids.isEmpty { withLock { self.allowedProductIDs = ids } }

        // Has to outlive configure(): a transaction StoreKit could not deliver earlier —
        // an Ask to Buy approval, a renewal, an interrupted purchase — arrives here on the
        // next launch and stays pending with Apple until finish() is called.
        // A second configure() would otherwise leave two listeners racing to finish the
        // same transaction.
        updatesTask?.cancel()
        updatesTask = Task { [weak self] in
            for await update in Transaction.updates {
                guard let self else { return }
                // Unverified payloads are deliberately left unfinished: finishing one would
                // quietly discard a transaction whose signature did not check out.
                guard case let .verified(transaction) = update else { continue }
                await transaction.finish()
                await self.resolveEntitlement()
            }
        }

        Task { [weak self] in
            await self?.resolveEntitlement()
            await self?.resolveStorefront()
        }
    }

    // MARK: - A1LifecycleObserving

    /// A lapsed subscription produces no `Transaction.updates` entry, so re-reading on
    /// foreground is the only way to notice an expiry that happened while backgrounded.
    public func applicationDidBecomeActive(_ application: UIApplication) {
        refresh()
    }

    // MARK: - Entitlement

    /// Whether Apple currently reports an active entitlement. Cached — safe during layout.
    public var hasActiveEntitlement: Bool { withLock { entitled } }

    /// Re-read `Transaction.currentEntitlements`. Completion runs on the main thread.
    public func refresh(completion: ((Bool) -> Void)? = nil) {
        Task { [weak self] in
            guard let self else { return }
            let active = await self.resolveEntitlement()
            guard let completion else { return }
            self.onMain { completion(active) }
        }
    }

    /// Observe entitlement changes. Fires immediately with the current value.
    /// Retain the token — it cancels the subscription when it deinits.
    @discardableResult
    public func observeEntitlement(_ handler: @escaping (Bool) -> Void) -> A1ObservationToken {
        let key = UUID()
        lock.lock()
        observers[key] = handler
        let current = entitled
        lock.unlock()

        onMain { handler(current) }

        return A1ObservationToken { [weak self] in
            guard let self else { return }
            self.withLock { self.observers[key] = nil }
        }
    }

    @discardableResult
    private func resolveEntitlement() async -> Bool {
        let allowed = withLock { self.allowedProductIDs }

        var active = false
        for await entitlement in Transaction.currentEntitlements {
            guard case let .verified(transaction) = entitlement,
                  transaction.revocationDate == nil,
                  !transaction.isUpgraded,
                  allowed.isEmpty || allowed.contains(transaction.productID) else { continue }
            // currentEntitlements should already exclude these, but a cached entitlement
            // read offline can still carry a date in the past.
            if let expiry = transaction.expirationDate, expiry <= Date() { continue }
            active = true
            break
        }

        publish(active)
        return active
    }

    private func publish(_ active: Bool) {
        lock.lock()
        guard active != entitled else { lock.unlock(); return }
        entitled = active
        let handlers = Array(observers.values)
        lock.unlock()

        onMain { handlers.forEach { $0(active) } }
    }

    // MARK: - Storefront

    /// Two-letter App Store country of the signed-in account, nil until it resolves.
    public var storefrontCountryCode: String? { withLock { storefront } }

    private func resolveStorefront() async {
        var resolved: String?
        for attempt in 0...Self.storefrontRetries {
            if attempt > 0 { try? await Task.sleep(nanoseconds: 5_000_000_000) }
            resolved = await Storefront.current?.countryCode
            if resolved != nil { break }
        }

        guard let code = resolved else {
            // Kept as an event, not reportError: an existing funnel counts these.
            analytics?.log(.event_app_user_country_fail)
            return
        }

        withLock { self.storefront = code }

        let region = regionCode
        analytics?.setUserProperty(code, for: Self.storefrontProperty)
        let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? ""
        analytics?.log(A1Event(.event_app_user_country,
                               parameters: ["storeCountry": code, "localCountry": region, "app_version": appVersion]))
        analytics?.log(A1Event(.event_app_user_store_country,
                               parameters: ["store": code, "app_version": appVersion]))
        analytics?.log(A1Event(.event_app_user_local_country,
                               parameters: ["locale": region, "app_version": appVersion]))
    }

    private var regionCode: String {
        if #available(iOS 16.0, macOS 13.0, *) {
            return Locale.current.region?.identifier ?? "Undefined"
        }
        return Locale.current.regionCode ?? "Undefined"
    }

    // MARK: - Helpers

    /// NSLock must not be held across an await — the compiler rejects taking one directly
    /// in an async context — so locked reads and writes from `Task` bodies come through here.
    private func withLock<T>(_ work: () -> T) -> T {
        lock.lock(); defer { lock.unlock() }
        return work()
    }

    private func onMain(_ work: @escaping () -> Void) {
        if Thread.isMainThread { work() } else { DispatchQueue.main.async(execute: work) }
    }
}
