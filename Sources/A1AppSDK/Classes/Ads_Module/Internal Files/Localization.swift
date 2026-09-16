//
//  Localization.swift
//  A1OfficeSDK
//
//  Created by Tushar Goyal on 06/09/23.
//

import Foundation

extension String {
    var localized: String{
      return NSLocalizedString(self, comment: "")
    }

    /// The app's translation when it defines the key, otherwise the SDK's own copy.
    ///
    /// The package ships no strings file, so a key the app has not translated would render
    /// as itself ("FORCE_TITLE") in a user-facing alert. An app overrides any of these by
    /// defining the key in its `Localizable.strings`.
    func localized(default fallback: String) -> String {
        Bundle.main.localizedString(forKey: self, value: fallback, table: nil)
    }
}

struct Localization {
    static let internetError: String = "INTERNET_ERROR".localized(default: "No internet connection.")
    static let networkError: String = "NETWORK_ERROR".localized(default: "A network error occurred. Please try again.")
    static let priceError: String = "PRICE_ERROR".localized(default: "Prices are unavailable right now.")
    static let fetchPlansError: String = "FETCH_PLANS_ERROR".localized(default: "Plans could not be loaded. Please try again.")
    static let updateNow: String = "UPDATE_NOW".localized(default: "Update Now")
    static let maybeLater: String = "MAYBE_LATER".localized(default: "Maybe Later")
    static let alertTitle: String = "ALERT".localized(default: "Alert")
    static let okTitle: String = "OK".localized(default: "OK")
    static let cancelTitle: String = "CANCEL".localized(default: "Cancel")
    static let forceTitle: String = "FORCE_TITLE".localized(default: "Update Required")
    static let forceMessage: String = "FORCE_MESSAGE".localized(default: "This version is no longer supported. Please update to continue.")
    static let optionalTitle: String = "OPTIONAL_TITLE".localized(default: "Update Available")
    static let optionalMessage: String = "OPTIONAL_MESSAGE".localized(default: "A new version is available with the latest improvements.")
}
