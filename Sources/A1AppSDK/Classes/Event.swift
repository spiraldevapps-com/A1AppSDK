//
//  Event.swift
//  A1OfficeSDK
//
//  Created by Tushar Goyal on 05/09/23.
//

import Foundation
import UIKit
import YandexMobileMetrica
import FBSDKCoreKit
import FirebaseAnalytics
import FirebaseCore

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
        if !appMetricaKey.isEmpty {
            let configuration = YMMYandexMetricaConfiguration.init(apiKey: appMetricaKey)
            configuration?.logs = true
            configuration?.userProfileID = userId
            YMMYandexMetrica.activate(with: configuration!)
        }
        logEvent(title: PurchaselyKey.event_app_first_open.rawValue)
    }

    public func logEvent(title: String, key: String, value: String) {
        if !appMetricaKey.isEmpty {
            YMMYandexMetrica.reportEvent(title, parameters: [key : value])
        }
        if firebase {
            Analytics.logEvent(title, parameters: [key: value])
        }
        if facebook {
            AppEvents.shared.logEvent(AppEvents.Name(title), parameters: [AppEvents.ParameterName(key): value])
        }
    }

    public func logEvent(title: String, params: [String: Any]? = nil) {
        if !appMetricaKey.isEmpty {
            YMMYandexMetrica.reportEvent(title, parameters: params)
        }
        if firebase {
            Analytics.logEvent(title, parameters: params)
        }
        if facebook {
            if let myparams = params {
                let appEventsParams = myparams.map { key, value in
                    (AppEvents.ParameterName(key), value)
                }
                let parameters = Dictionary(uniqueKeysWithValues: appEventsParams)
                AppEvents.shared.logEvent(AppEvents.Name(title), parameters: parameters)
            } else {
                AppEvents.shared.logEvent(AppEvents.Name(title), parameters: nil)
            }
        }
    }
    
    public func logProOpenedEvent(title: String, from: String) {
        if !appMetricaKey.isEmpty {
            YMMYandexMetrica.reportEvent(title, parameters: [proOpenFromKey: from])
        }
        if firebase {
            Analytics.logEvent(title, parameters: [proOpenFromKey: from])
        }
        if facebook {
            AppEvents.shared.logEvent(AppEvents.Name(title), parameters: [AppEvents.ParameterName(proOpenFromKey): from])
        }
    }

    public func logFacebookEvent(name: String, params: [String: String]) {
        if facebook {
            let appEventsParams = params.map { key, value in
                (AppEvents.ParameterName(key), value)
            }
            let parameters = Dictionary(uniqueKeysWithValues: appEventsParams)
            AppEvents.shared.logEvent(AppEvents.Name(name), parameters: parameters)
        }
        //Add same events for google as well
        if firebase {
            Analytics.logEvent(name, parameters: params)
        }
    }

    public func logEvent(title: String, keys: [String] = [], values: [String] = []) {
        let params = setParam(keys: keys, values: values)
        logEvent(title: title, params: params)
    }
    
    private func setParam(keys: [String], values: [String]) -> [String: String] {
        var params: [String: String] = [:]
        for (index, key) in keys.enumerated() {
            params.updateValue(values[index], forKey: key)
        }
        return params
    }

    
}
