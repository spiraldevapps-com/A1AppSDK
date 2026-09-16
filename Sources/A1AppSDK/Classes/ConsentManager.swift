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

    /// Whether UMP allows ad requests: consent obtained, or not required in this region.
    public var canRequestAds: Bool { UMPConsentInformation.sharedInstance.canRequestAds }

    /// Whether the consent form still has to be answered before ads may be requested.
    public var isConsentRequired: Bool { UMPConsentInformation.sharedInstance.consentStatus == .required }

    /// UMP has not answered at all this launch — no info update succeeded and nothing is cached.
    var isConsentStatusUnknown: Bool { UMPConsentInformation.sharedInstance.consentStatus == .unknown }

    /// Runs after the consent form has been answered. The consent module hooks this to
    /// re-run its gate, which is how ads start after the form.
    var onConsentFormDismissed: (() -> Void)?
    
    /// Helper method to call the UMP SDK methods to request consent information and load/present a
    /// consent form if necessary.
    public func gatherConsent(completion: (() -> Void)? = nil) {
        let parameters = UMPRequestParameters()
        // Requesting an update to consent information should be called on every app launch.
        UMPConsentInformation.sharedInstance.requestConsentInfoUpdate(with: parameters) {
            requestConsentError in
            if requestConsentError == nil {
                EventManager.shared.logEvent(title: GDPRKeys.event_app_home_gdpr_form_loaded.rawValue)
            }
            // Always signal, success or failure — ads must not be blocked forever on a
            // network error, and callers gate their own loading on this.
            completion?()
        }
    }
    
    /// Present the consent form from `viewController` when consent is required.
    ///
    /// The completion runs exactly once on every path — load failure, nothing required,
    /// refused present, dismissal — so a caller that navigates on from it is never stranded.
    public func showGDPR(from viewController: UIViewController, completionHandler: @escaping () -> Void) {
        var isFinished = false
        let finish = { [weak self] (formWasAnswered: Bool) in
            guard !isFinished else { return }
            isFinished = true
            if formWasAnswered { self?.onConsentFormDismissed?() }
            completionHandler()
        }
        UMPConsentForm.load { (form, error) in
            if let error = error {
                print("Failed to load form: \(error.localizedDescription)")
                finish(false)
                return
            }
            guard let form = form else { finish(false); return }
            DispatchQueue.main.async {
                guard UMPConsentInformation.sharedInstance.consentStatus == .required else { finish(false); return }
                EventManager.shared.logEvent(title: GDPRKeys.event_app_home_gdpr_form_shown.rawValue)
                // A refused present (controller not in a window) reports an error: the
                // form was not answered, so there is nothing for the gate to re-check.
                form.present(from: viewController) { presentError in finish(presentError == nil) }
            }
        }
    }

    /// Kept for apps written against 1.0.x. The ad parameters are ignored: the ads module
    /// re-applies its own last configuration once consent resolves, so a snapshot taken
    /// before the form can no longer overwrite a fresher one.
    @available(*, deprecated, message: "Use showGDPR(from:completionHandler:). Ads reconfigure themselves after consent.")
    public func showGDPR(from viewController: UIViewController, adConfig: AdsConfiguration, isPro: Bool, completionHandler: @escaping () -> Void) {
        showGDPR(from: viewController, completionHandler: completionHandler)
    }
}
