//
//  A1EventKey.swift
//  A1AppSDK
//
//  Every analytics name the SDK emits, declared in one place.
//
//  Two vocabularies, deliberately separate:
//  - `A1EventKey`      — product events shared across the A1 apps. These names predate the SDK
//                        (they came with the apps' common origin) and every dashboard is keyed on
//                        them, so they are kept verbatim. An app whose names differ remaps with
//                        `A1Configuration.eventNameOverrides` rather than editing the SDK.
//  - `A1DiagnosticKey` — signals the SDK invented about its own health. Namespaced `a1sdk_` so
//                        they can never be mistaken for, or collide with, an app's vocabulary.
//
//  Adapters reference these cases; they must not type event strings inline.
//

import Foundation

/// Product events the SDK emits on behalf of the app.
public enum A1EventKey: String, CaseIterable {

    // MARK: Subscription / paywall
    case event_subs_paywall_load_started
    case event_subs_paywall_load_failed
    case event_subs_paywall_show_requested
    case event_subs_paywall_screen_shown
    case event_subs_paywall_plan_selected
    case event_subs_paywall_payment_failed
    case event_subs_purchase_started
    case event_subs_purchase_cancelled
    case event_subs_purchase_acknowledged
    case event_subs_restore_started
    case event_app_paywall_cross_clicked
    case event_app_paywall_restore_acknowledged

    // MARK: Subscription vendor errors
    case adapty_configuration_successful
    case adapty_configuration_error
    case adapty_customer_id_error
    case adapty_profile_error
    case adapty_paywall_error
    case adapty_rendering_error
    case adapty_productdetailloading_error
    case adapty_purchasefailed_error
    case adapty_restorepurchase_error

    // MARK: Lifecycle
    case event_app_first_open

    // MARK: Identity
    case event_app_login_successfully
    case event_app_login_failed_again
    case firebase_authentication_error

    // MARK: Remote config
    case remote_config_fetch_successful
    case firebase_remoteconfig_error

    // MARK: Storefront
    case event_app_user_country
    case event_app_user_store_country
    case event_app_user_local_country
    case event_app_user_country_fail

    // MARK: Attribution
    case event_app_asa_data
    case event_app_search_ads_attributed
    case search_ads_attribution_error
}

/// SDK health signals. Namespaced so they are visibly not app vocabulary.
public enum A1DiagnosticKey: String, CaseIterable {
    case firebase_configure_failed        = "a1sdk_firebase_configure_failed"
    case auth_no_firebase                 = "a1sdk_auth_no_firebase"
    case remoteconfig_no_firebase         = "a1sdk_remoteconfig_no_firebase"
    case messaging_no_firebase            = "a1sdk_messaging_no_firebase"
    case appmetrica_config_invalid        = "a1sdk_appmetrica_config_invalid"
    case clarity_init_failed              = "a1sdk_clarity_init_failed"
    case performance_trace_rejected       = "a1sdk_performance_trace_rejected"
    case consent_not_configured           = "a1sdk_consent_not_configured"
    case app_update_configuration_error   = "a1sdk_app_update_configuration_error"
    case intercom_push_token_error        = "a1sdk_intercom_push_token_error"
    case adapty_not_activated             = "a1sdk_adapty_not_activated"
    case adapty_integration_identifier_error = "a1sdk_adapty_integration_identifier_error"
    case att_prompt_shown                 = "a1sdk_att_prompt_shown"
    case att_prompt_result                = "a1sdk_att_prompt_result"
    case rating_prompt_requested          = "a1sdk_rating_prompt_requested"
    case network_status_changed           = "a1sdk_network_status_changed"
}

// MARK: - Typed entry points

public extension A1Event {
    init(_ key: A1EventKey, parameters: [String: Any]? = nil) {
        self.init(key.rawValue, parameters: parameters)
    }
    init(_ key: A1EventKey, keys: [String], values: [String]) {
        self.init(key.rawValue, keys: keys, values: values)
    }
    init(_ key: A1DiagnosticKey, parameters: [String: Any]? = nil) {
        self.init(key.rawValue, parameters: parameters)
    }
}

public extension AnalyticsProvider {
    func log(_ key: A1EventKey, parameters: [String: Any]? = nil) {
        log(A1Event(key, parameters: parameters))
    }
    func log(_ key: A1DiagnosticKey, parameters: [String: Any]? = nil) {
        log(A1Event(key, parameters: parameters))
    }
    func reportError(_ key: A1EventKey, message: String, parameters: [String: Any]? = nil) {
        reportError(key.rawValue, message: message, parameters: parameters)
    }
    func reportError(_ key: A1DiagnosticKey, message: String, parameters: [String: Any]? = nil) {
        reportError(key.rawValue, message: message, parameters: parameters)
    }
}
