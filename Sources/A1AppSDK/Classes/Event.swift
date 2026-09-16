//
//  Event.swift
//  A1OfficeSDK
//
//  Created by Tushar Goyal on 05/09/23.
//

import Foundation
import FBSDKCoreKit
import FirebaseAnalytics
import AppMetricaCore

public enum PurchaselyKey: String {
    
    // MARK: - First Time Application Event
    case event_app_first_open
    
    // MARK: - Purchasely
    case event_subs_purchasely_load_started
    case event_subs_purchasely_show_requested
    case event_subs_purchasely_screen_shown
    case event_subs_purchasely_screen_cross_clicked
    case event_subs_purchasely_payment_failed
    case event_subs_purchase_acknowledged // with params

}

public enum AdsKey: String {
    
    // MARK: - Ads
    case event_ad_banner_load_start
    case event_ad_banner_load_failed
    case event_ad_banner_loaded
    case event_ad_banner_show_requested
    case event_ad_banner_shown
    case event_ad_banner_show_failed

    case event_ad_inter_load_start
    case event_ad_inter_load_failed
    case event_ad_inter_loaded
    case event_ad_inter_show_requested
    case event_ad_inter_shown
    case event_ad_inter_show_failed

    case event_ad_appopen_load_start
    case event_ad_appopen_load_failed
    case event_ad_appopen_loaded
    case event_ad_appopen_show_requested
    case event_ad_appopen_shown
    case event_ad_appopen_show_failed
    
    case event_ad_rewarded_load_start
    case event_ad_rewarded_load_failed
    case event_ad_rewarded_loaded
    case event_ad_rewarded_show_requested
    case event_ad_rewarded_shown
    case event_ad_rewarded_show_failed
    
}

public enum AppUpdateKey: String {
    // MARK: - App Update
    case event_force_update_home_pop_up_loaded
    case event_force_update_home_pop_up_shown
    case event_force_update_home_update_now_clicked
    case event_optional_update_home_pop_up_loaded
    case event_optional_update_home_pop_up_shown
    case event_optional_update_home_update_now_clicked
    case event_optional_update_home_may_be_later_clicked
}

public enum AppErrorKey: String {
    // MARK: - App Error
    case event_ad_error_load_failed // added in commons
    case event_ad_error_show_failed // added in commons
    case event_subs_error_purchase_failed // added in commons
    case event_app_error_conversion_failed // Need to add via app
    case event_app_error_file_open_failed // Need to add via app
    case event_app_error_pdf_conversion_click_failed // Need to add via app
    case event_app_error_purchase_click_failed
}

public enum GDPRKeys:String {
    case event_app_home_gdpr_form_loaded
    case event_app_home_gdpr_form_shown
}

public class EventManager: NSObject {
    let proOpenFromKey = "pro_opened_from"
    public static var shared = EventManager()
    private var appMetricaKey = ""
    private var firebase = true
    private var facebook = true

    public func configureEventManager(appMetricaKey: String = "",userId: String = "", firebase: Bool = true, facebook: Bool = true) {
        self.appMetricaKey = appMetricaKey
        self.firebase = firebase
        self.facebook = facebook
        // Failable: a malformed key returns nil, and force-unwrapping it crashed on launch.
        guard !appMetricaKey.isEmpty,
              let configuration = AppMetricaConfiguration(apiKey: appMetricaKey) else { return }
        configuration.userProfileID = userId
        configuration.areLogsEnabled = true
        AppMetrica.activate(with: configuration)
    }

    /// Meta keys its parameters by `ParameterName`. Built with `uniquingKeysWith:` instead of
    /// `uniqueKeysWithValues:` — the latter traps at runtime if two keys collapse to the same
    /// ParameterName. No event name or value changes.
    private static func metaParameters(_ params: [String: Any]) -> [AppEvents.ParameterName: Any] {
        Dictionary(params.map { (AppEvents.ParameterName($0.key), $0.value) },
                   uniquingKeysWith: { _, latest in latest })
    }

    /// Shared fan-out for the entry points that always carry parameters. The order —
    /// AppMetrica, then Firebase, then Meta — is what the dashboards have always received.
    private func fanOut(_ title: String, _ parameters: [String: Any]?) {
        // Every legacy overload lands here. Once A1SDK is running it owns the sinks, so forward
        // rather than fan out twice — previously only one overload did this, and the ad
        // error-detail events (key/value overload) silently skipped AppMetrica.
        if A1SDK.shared.isConfigured {
            A1SDK.shared.analytics.log(A1Event(title, parameters: parameters))
            return
        }
        if !appMetricaKey.isEmpty {
            AppMetrica.reportEvent(name: title, parameters: parameters)
        }
        if firebase {
            Analytics.logEvent(title, parameters: parameters)
        }
        if facebook {
            AppEvents.shared.logEvent(AppEvents.Name(title), parameters: parameters.map(Self.metaParameters))
        }
    }

    public func logEvent(title: String, key: String, value: String) {
        fanOut(title, [key: value])
    }

    public func logEvent(title: String, params: [String: Any]? = nil) {
        fanOut(title, params)
    }

    public func logProOpenedEvent(title: String, from: String) {
        fanOut(title, [proOpenFromKey: from])
    }

    public func logFacebookEvent(name: String, params: [String: String]) {
        if facebook {
            AppEvents.shared.logEvent(AppEvents.Name(name), parameters: Self.metaParameters(params))
        }
        //Add same events for google as well
        if firebase {
            Analytics.logEvent(name, parameters: params)
        }
    }

    public func logEvent(title: String, keys: [String] = [], values: [String] = []) {
        // `zip` stops at the shorter side: a keys/values length mismatch used to trap here.
        let params: [String: String] = Dictionary(zip(keys, values), uniquingKeysWith: { _, latest in latest })
        logEvent(title: title, params: params)
    }
}
