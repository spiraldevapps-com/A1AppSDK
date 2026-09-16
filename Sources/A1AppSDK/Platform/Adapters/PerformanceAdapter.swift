//
//  PerformanceAdapter.swift
//  A1AppSDK
//
//  Firebase Performance traces. Replaces the hand-written PerformanceTrackingManager in
//  each app, whose shared [String: Trace] dictionary was both a data race and a leak —
//  a trace never stopped stayed in the dictionary and was never reported.
//

import Foundation
import FirebaseCore
import FirebasePerformance

// MARK: - Handle

/// An in-flight trace.
///
/// A value, so it can be captured by the completion handler that ends the work it measures
/// and passed across files without a lookup key. The vendor trace travels inside the handle
/// rather than in a table the adapter has to prune, so a handle that is simply dropped
/// reports nothing and leaks nothing.
public struct A1TraceHandle {

    public let name: String
    fileprivate let id = UUID()
    fileprivate let trace: Trace

    fileprivate init(_ name: String, _ trace: Trace) {
        self.name = name
        self.trace = trace
    }

    /// Cumulative counter — retries, bytes, cache hits. Creates the counter on first use.
    public func increment(_ counter: String, by amount: Int64 = 1) {
        trace.incrementMetric(counter, by: amount)
    }

    public func setValue(_ value: Int64, forCounter counter: String) {
        trace.setValue(value, forMetric: counter)
    }

    /// Attributes are what the Firebase console segments a trace by (placement, source…).
    /// Firebase allows five per trace and truncates over-long names and values.
    public func setValue(_ value: String, forAttribute attribute: String) {
        trace.setValue(value, forAttribute: attribute)
    }
}

// MARK: - Adapter

public final class PerformanceAdapter: A1Module {

    /// Immediately after Firebase core, ahead of every other module, so the boot trace it
    /// opens covers the whole launch rather than starting at the analytics phase.
    public var phase: A1BootPhase { .custom(after: .bootstrap) }

    private let lock = NSLock()
    /// Traces not yet stopped. A handle is a value and can be copied, so the same trace can
    /// reach `stop(_:)` from several branches of one completion handler; Firebase logs an
    /// error when an already-stopped trace is stopped again.
    private var running: Set<UUID> = []
    /// Launch-path traces, held by name because they start and end in different files.
    private var stages: [String: A1TraceHandle] = [:]

    private var isEnabled = false
    private var analytics: AnalyticsProvider?

    public init() {}

    /// Name of the launch trace every app gets for free. SDK-namespaced.
    public static let bootTraceName = "a1sdk_boot"
    private var bootTrace: A1TraceHandle?

    public func configure(context: A1ModuleContext) {
        analytics = context.analytics

        // Firebase Performance raises an ObjC exception — not a catchable Swift error — when
        // a trace is created before FirebaseApp.configure(). Without Firebase, stay off.
        guard FirebaseApp.app() != nil else { return }

        // dataCollectionEnabled is persisted by Firebase and overrides Info.plist once set,
        // so only write it when the app actually asked; otherwise adopt what is already there.
        if let enabled = context.configuration.isPerformanceMonitoringEnabled {
            Performance.sharedInstance().isDataCollectionEnabled = enabled
            isEnabled = enabled
        } else {
            isEnabled = Performance.sharedInstance().isDataCollectionEnabled
        }

        // Opened as early as a trace legally can be (this module boots second, right after
        // FirebaseCore). A1SDK closes it once boot completes and attaches per-module timings.
        bootTrace = startTrace(Self.bootTraceName)
    }

    // MARK: - Boot trace (driven by A1SDK)

    /// One metric per module: how long its `configure(context:)` took.
    func recordBootModule(_ identifier: String, milliseconds: Int64) {
        bootTrace?.setValue(milliseconds, forCounter: "\(identifier)_ms")
    }

    /// Close the launch trace with the end-to-end figure.
    func finishBootTrace(totalMilliseconds: Int64) {
        guard let trace = bootTrace else { return }
        trace.setValue(totalMilliseconds, forCounter: "total_ms")
        stop(trace)
        bootTrace = nil
    }

    // MARK: - Traces

    /// Start a trace. Nil when performance collection is off, so call sites hold an optional
    /// handle instead of testing configuration themselves.
    public func startTrace(_ name: String) -> A1TraceHandle? {
        guard isEnabled else { return nil }
        guard let trace = Performance.startTrace(name: name) else {
            // Worth knowing: the measurement vanished silently, which is exactly how the
            // legacy manager sat fully commented out for months without anyone noticing.
            analytics?.reportError(.performance_trace_rejected,
                                   message: "Firebase refused a trace named '\(name)'",
                                   parameters: nil)
            return nil
        }

        let handle = A1TraceHandle(name, trace)
        lock.lock()
        running.insert(handle.id)
        lock.unlock()
        return handle
    }

    /// Stop and report. Stopping the same handle twice does nothing.
    public func stop(_ handle: A1TraceHandle) {
        lock.lock()
        let wasRunning = running.remove(handle.id) != nil
        lock.unlock()

        if wasRunning { handle.trace.stop() }
    }

    /// Time a block. The trace is reported whether the work returns or throws.
    @discardableResult
    public func measure<T>(_ name: String, _ work: () throws -> T) rethrows -> T {
        let handle = startTrace(name)
        defer { if let handle { stop(handle) } }
        return try work()
    }

    // MARK: - Launch path

    /// Begin a launch stage.
    ///
    /// Launch timings start and end in different files — the splash screen begins
    /// `splash_to_home`, the dashboard ends it — so these are held by name. The names stay
    /// in the host app; the SDK owns the mechanics, not the vocabulary.
    @discardableResult
    public func beginStage(_ name: String) -> A1TraceHandle? {
        guard let handle = startTrace(name) else { return nil }

        lock.lock()
        // Re-entering a stage abandons the previous trace rather than reporting a duration
        // that spans both attempts: a Firebase trace that is never stopped is never sent.
        if let displaced = stages.updateValue(handle, forKey: name) {
            running.remove(displaced.id)
        }
        lock.unlock()
        return handle
    }

    /// End a stage begun with `beginStage`. An unknown or already-ended name does nothing,
    /// so each of the several paths that can reach a screen may call it.
    public func endStage(_ name: String) {
        lock.lock()
        let handle = stages.removeValue(forKey: name)
        lock.unlock()

        if let handle { stop(handle) }
    }
}
