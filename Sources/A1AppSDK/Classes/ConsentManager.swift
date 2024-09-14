//
//  ConsentManager.swift
//  A1Office
//
//  Created by Tushar Goyal on 06/03/24.
//

import Foundation
import UserMessagingPlatform


public class ConsentManager {
    public static let shared = ConsentManager()
    
    public var isPrivacyOptionsRequired: Bool {
        return UMPConsentInformation.sharedInstance.privacyOptionsRequirementStatus == .required
    }
    
    /// Helper method to call the UMP SDK methods to request consent information and load/present a
    /// consent form if necessary.
    public func gatherConsent() {
        let parameters = UMPRequestParameters()
        // Requesting an update to consent information should be called on every app launch.
        UMPConsentInformation.sharedInstance.requestConsentInfoUpdate(with: parameters) {
            requestConsentError in
            guard requestConsentError == nil else {
                return
            }
            EventManager.shared.logEvent(title: GDPRKeys.event_app_home_gdpr_form_loaded.rawValue)
        }
    }
    
    /// Helper method to call the UMP SDK method to present the privacy options form.
    ///
    /// 
    public func showGDPR(from viewController: UIViewController, adConfig: AdsConfiguration, isPro: Bool, completionHandler: @escaping () -> Void) {
        UMPConsentForm.load { [weak self] (form, error) in
            if let error = error {
                print("Failed to load form: \(error.localizedDescription)")
                completionHandler()
            } else if let form = form {
                DispatchQueue.main.async {
                    // Show the consent form
                    guard UMPConsentInformation.sharedInstance.consentStatus == .required else {completionHandler(); return}
                    if let vc = UIApplication.shared.windows.first?.rootViewController {
                        EventManager.shared.logEvent(title: GDPRKeys.event_app_home_gdpr_form_shown.rawValue)
                        form.present(from: vc) { (dismissError) in
                            if UMPConsentInformation.sharedInstance.consentStatus != .required {
                                AdsHandler.shared.configureAds(config: adConfig, pro: isPro)
                            }
                            completionHandler()
                        }
                    }
                }
            }
        }
    }
}
