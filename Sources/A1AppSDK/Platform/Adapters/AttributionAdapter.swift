//
//  AttributionAdapter.swift
//  A1AppSDK
//
//  Apple Search Ads attribution (AdServices), as a module. Replaces the hand-written
//  AppAtributionManager four of the five apps carried a private copy of.
//

import Foundation
import AdServices

public final class AttributionAdapter: A1Module {

    /// `.foundation`, not `.analytics`: the fetch is a network round-trip Apple only
    /// answers a short while after install, so it is started as early as possible. Events
    /// raised before the analytics phase are buffered by the dispatcher, not lost.
    public var phase: A1BootPhase { .foundation }

    // MARK: - Constants

    private static let endpoint = URL(string: "https://api-adservices.apple.com/api/v1/")!
    private static let fetchedKey = "com.a1appsdk.attribution.fetched"
    private static let payloadKey = "com.a1appsdk.attribution.payload"
    private static let maxRetries = 5

    /// Apple's response key, the parameter name the apps' dashboards already use, and
    /// whether the field is also worth carrying as a user-scoped trait. Click date and
    /// country stay event parameters only.
    private static let reportedFields: [(response: String, parameter: String, isTrait: Bool)] = [
        ("keyword",         "keyword",           true),
        ("campaignId",      "campaign_id",       true),
        ("campaignName",    "campaign_name",     true),
        ("adGroupId",       "ad_group_id",       true),
        ("adGroupName",     "ad_group_name",     true),
        ("keywordId",       "keyword_id",        true),
        ("clickDate",       "click_date",        false),
        ("countryOrRegion", "country_or_region", false)
    ]

    // MARK: - State

    private let lock = NSLock()
    private var storedToken: String?
    private var storedPayload: [String: Any]?
    private var waiters: [([String: Any]?) -> Void] = []
    private var retryCount = 0
    private var resolved = false
    private var analytics: AnalyticsProvider?

    public init() {}

    // MARK: - Public surface

    /// The AdServices token posted this launch. Nil once the install has been fetched —
    /// Apple's tokens are short-lived, so a stale one is worse than none.
    public var attributionToken: String? {
        lock.lock(); defer { lock.unlock() }
        return storedToken
    }

    /// Apple's raw attribution response, cached across launches. Hand it to a subscription
    /// vendor via `setIntegrationIdentifier(key:value:)` or read individual fields from it.
    public var payload: [String: Any]? {
        lock.lock(); defer { lock.unlock() }
        return storedPayload
    }

    /// Run `handler` on the main queue once attribution has settled — immediately if it
    /// already has. The payload is nil when the fetch failed or the install is not attributed.
    public func whenResolved(_ handler: @escaping ([String: Any]?) -> Void) {
        lock.lock()
        guard resolved else {
            waiters.append(handler)
            lock.unlock()
            return
        }
        let result = storedPayload
        lock.unlock()
        DispatchQueue.main.async { handler(result) }
    }

    // MARK: - A1Module

    public func configure(context: A1ModuleContext) {
        analytics = context.analytics

        // The fetch runs once per install, but a host still needs the payload on every
        // launch to forward as a vendor integration id, so the response is persisted.
        if let cached = UserDefaults.standard.dictionary(forKey: Self.payloadKey) {
            lock.lock(); storedPayload = cached; lock.unlock()
            publishUserProperties(cached)
        }

        guard context.configuration.isSearchAdsAttributionEnabled,
              !UserDefaults.standard.bool(forKey: Self.fetchedKey) else {
            resolve()
            return
        }

        // attributionToken() is a synchronous call that can block; keep it, and the POST
        // it feeds, off the launch path.
        DispatchQueue.global(qos: .utility).async { [weak self] in self?.fetch() }
    }

    // MARK: - Fetch

    private func fetch() {
        let token: String
        do {
            token = try AAAttribution.attributionToken()
        } catch {
            // Throws on Simulator and wherever no token exists. The marker stays unset,
            // so a device that later has one still reports on a subsequent launch.
            analytics?.reportError(.search_ads_attribution_error,
                                   message: error.localizedDescription,
                                   parameters: nil)
            resolve()
            return
        }

        lock.lock(); storedToken = token; lock.unlock()
        post(token)
    }

    private func post(_ token: String) {
        var request = URLRequest(url: Self.endpoint)
        request.httpMethod = "POST"
        request.httpBody = Data(token.utf8)
        request.setValue("text/plain", forHTTPHeaderField: "Content-Type")

        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            guard let self else { return }
            let status = (response as? HTTPURLResponse)?.statusCode ?? -1
            guard (200...299).contains(status),
                  let data,
                  let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
                self.retry(token, reason: error?.localizedDescription ?? "HTTP \(status)")
                return
            }
            self.store(json)
        }.resume()
    }

    /// Apple's endpoint 404s for a window after install while the token propagates, so a
    /// failed request is retried rather than read as "not attributed". Only the final
    /// failure is reported — an early 404 is expected, not an incident.
    private func retry(_ token: String, reason: String) {
        lock.lock()
        guard retryCount < Self.maxRetries else {
            lock.unlock()
            analytics?.reportError(.search_ads_attribution_error,
                                   message: reason,
                                   parameters: ["attempts": Self.maxRetries])
            resolve()
            return
        }
        retryCount += 1
        let attempt = retryCount
        lock.unlock()

        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + pow(2.0, Double(attempt))) {
            [weak self] in self?.post(token)
        }
    }

    // MARK: - Reporting

    private func store(_ json: [String: Any]) {
        // UserDefaults and the analytics sinks both reject anything that is not a scalar,
        // and Apple's JSON can carry a null.
        let payload = json.filter { $0.value is String || $0.value is NSNumber }

        UserDefaults.standard.set(payload, forKey: Self.payloadKey)
        // Written only after a successful round-trip, so a first launch spent offline
        // tries again next launch instead of losing the attribution permanently.
        UserDefaults.standard.set(true, forKey: Self.fetchedKey)

        analytics?.log(A1Event(.event_app_asa_data, parameters: payload))

        if payload["attribution"] as? Bool == true {
            analytics?.log(A1Event(.event_app_search_ads_attributed,
                                   keys: Self.reportedFields.map { $0.parameter },
                                   values: Self.reportedFields.map { text(payload[$0.response]) ?? "" }))
            publishUserProperties(payload)
        }

        resolve(payload)
    }

    private func publishUserProperties(_ payload: [String: Any]) {
        guard payload["attribution"] as? Bool == true else { return }
        for field in Self.reportedFields where field.isTrait {
            analytics?.setUserProperty(text(payload[field.response]), for: "asa_" + field.parameter)
        }
    }

    /// Passing `nil` keeps whatever was restored from the cache.
    private func resolve(_ payload: [String: Any]? = nil) {
        lock.lock()
        storedPayload = payload ?? storedPayload
        resolved = true
        let pending = waiters
        let result = storedPayload
        waiters.removeAll()
        lock.unlock()

        guard !pending.isEmpty else { return }
        DispatchQueue.main.async { pending.forEach { $0(result) } }
    }

    private func text(_ value: Any?) -> String? {
        guard let value else { return nil }
        let string = "\(value)"
        return string.isEmpty ? nil : string
    }
}
