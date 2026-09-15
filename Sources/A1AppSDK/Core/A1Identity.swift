//
//  A1Identity.swift
//  A1AppSDK
//
//  Identity resolves in two stages, by necessity.
//
//  On a first launch there is no user id yet — anonymous sign-in is a network round-trip
//  and launch must not block on it. So modules boot with an empty id, which is correct
//  and expected, and are re-identified once the real id arrives.
//
//  The second stage is what this type exists to make reliable. Previously each app
//  re-identified each vendor by hand, in different places, and it was easy to miss one.
//  Here a module subscribes once and is guaranteed to be told.
//
//  LOCKING RULE: `lock` is a plain NSLock and is therefore NOT recursive. Nothing that can
//  run arbitrary caller code — a handler, or the release of a stored closure, which may drop
//  the last reference to an A1ObservationToken and run its deinit — may happen while it is
//  held. Every method below takes the lock, copies what it needs, unlocks, and only then
//  calls out. Keep it that way.
//

import Foundation

/// Cancels an identity subscription. Discard it and the subscription is removed.
public final class A1ObservationToken {
    private let onCancel: () -> Void
    private let stateLock = NSLock()
    private var cancelled = false

    init(onCancel: @escaping () -> Void) { self.onCancel = onCancel }

    public func cancel() {
        // Cancellation can race between a caller and deinit; run the teardown exactly once.
        stateLock.lock()
        guard !cancelled else { stateLock.unlock(); return }
        cancelled = true
        stateLock.unlock()

        onCancel()
    }

    deinit { cancel() }
}

/// The shared user identity every module keys off.
public final class A1Identity {

    private let lock = NSLock()
    private var storage = ""
    private var observers: [UUID: (String) -> Void] = [:]

    public init(userID: String = "") {
        storage = userID
    }

    /// Current user id. Empty until sign-in resolves — that is a valid state, not an error.
    public var userID: String {
        lock.lock(); defer { lock.unlock() }
        return storage
    }

    /// `true` once a real id has been established.
    public var isResolved: Bool { !userID.isEmpty }

    /// Publish a new id. Observers are notified on the main queue, and only on an actual change.
    ///
    /// Safe to call from inside an observer handler: handlers run with no lock held.
    public func update(userID newValue: String) {
        lock.lock()
        guard newValue != storage else { lock.unlock(); return }
        storage = newValue
        let handlers = Array(observers.values)
        lock.unlock()

        notify(handlers, with: newValue)
    }

    /// Observe the identity.
    ///
    /// The handler fires immediately with the current value — including the empty one — so a
    /// module registered after sign-in has already resolved is never left holding a stale id.
    @discardableResult
    public func observe(_ handler: @escaping (String) -> Void) -> A1ObservationToken {
        let key = UUID()

        lock.lock()
        observers[key] = handler
        let current = storage
        lock.unlock()

        notify([handler], with: current)

        return A1ObservationToken { [weak self] in
            guard let self else { return }
            self.lock.lock()
            // Take the closure out under the lock but release it outside: a handler can hold
            // the last reference to another token, whose deinit re-enters cancel() and would
            // deadlock on this non-recursive lock.
            let removed = self.observers.removeValue(forKey: key)
            self.lock.unlock()
            withExtendedLifetime(removed) {}
        }
    }

    private func notify(_ handlers: [(String) -> Void], with value: String) {
        guard !handlers.isEmpty else { return }
        if Thread.isMainThread {
            handlers.forEach { $0(value) }
        } else {
            DispatchQueue.main.async { handlers.forEach { $0(value) } }
        }
    }
}
