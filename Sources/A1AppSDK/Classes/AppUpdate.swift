//
//  AppUpdate.swift
//  A1Office
//
//  Created by Navnidhi Sharma on 19/01/24.
//

import UIKit

// Prerequisits
// Firebase configure method must call before requesting the firebase config
// app store url must be set before checking update
public class AppUpdate {
    public static var shared = AppUpdate()
    private var isOptionalUpdateShown = false
    public var versionConfig: VersionConfig?
    public var appStoreURL: String?
    /// The alert currently on screen, if any. Weak: when the alert goes — by a button, or
    /// torn down with a presenter the app dismissed under it — the reference clears itself.
    private weak var presentedAlert: UIAlertController?
    /// `true` while an update alert is on screen. Derived from the alert itself rather than
    /// latched, so it cannot wedge when a presentation is refused or torn down.
    public var isPopupShowing: Bool { presentedAlert?.presentingViewController != nil }

    public func configureAppUpdate(url: String, config: VersionConfig) {
        appStoreURL = url
        versionConfig = config
    }
    
    /**
     Checks for Firebase remote config and check if update needed.
     
     - Parameter success: Completion handler gives FirebaseConfig model
     - Parameter failure: Completion handler gives Error
     */
    public func checkUpdate(canCheckOptionalUpdate: Bool = true) {
        guard let config = versionConfig else { return }
        if !checkForceUpdateNeeded(config: config), canCheckOptionalUpdate {
            _ = checkOptionalUpdateNeeded(config: config)
        }
    }
    
    /// Checks for Firebase - Remote config properties for server maintenance and application update
    /// - Parameter config: FirebaseConfig model
    private func checkForceUpdateNeeded(config: VersionConfig) -> Bool {
        guard !config.minVersion.isEmpty, let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String else {
            return false
        }
        if config.minVersion.compare(appVersion, options: .numeric) == .orderedDescending {
            print("force version is newer than app version")
            EventManager.shared.logEvent(title: AppUpdateKey.event_force_update_home_pop_up_loaded.rawValue)
            let handler: (UIAlertAction) -> () = { [weak self] (alert) in
                EventManager.shared.logEvent(title: AppUpdateKey.event_force_update_home_update_now_clicked.rawValue)
                if let urlString = self?.appStoreURL {
                    Utility.openAppStore(urlString: urlString)
                }
            }
            DispatchQueue.main.async { [weak self] in
                // One prompt at a time: a second check while the alert is up must not stack
                // another on top of it (or count a second impression).
                guard let self, !self.isPopupShowing else { return }
                self.presentedAlert = Utility.showAlert(title:Localization.forceTitle, message:Localization.forceMessage, defaultTitle: Localization.updateNow, defaultHandler: handler)
                if self.presentedAlert != nil {
                    EventManager.shared.logEvent(title: AppUpdateKey.event_force_update_home_pop_up_shown.rawValue)
                }
            }
            return true
        } else {
            return false
        }
    }
    
    private func checkOptionalUpdateNeeded(config: VersionConfig) -> Bool {
        guard isOptionalUpdateShown == false, let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String else { return false }
        guard !config.stableVersion.isEmpty else {
            return false
        }
        if config.stableVersion.compare(appVersion, options: .numeric) == .orderedDescending {
            print("optional version is newer than app version")
            EventManager.shared.logEvent(title: AppUpdateKey.event_optional_update_home_pop_up_loaded.rawValue)
            let handler: (UIAlertAction) -> () = { [weak self] (alert) in
                self?.isOptionalUpdateShown = true
                EventManager.shared.logEvent(title: AppUpdateKey.event_optional_update_home_may_be_later_clicked.rawValue)
            }
            let handler1: (UIAlertAction) -> () = { [weak self] (alert) in
                self?.isOptionalUpdateShown = true
                EventManager.shared.logEvent(title: AppUpdateKey.event_optional_update_home_update_now_clicked.rawValue)
                if let urlString = self?.appStoreURL {
                    Utility.openAppStore(urlString: urlString)
                }
            }
            DispatchQueue.main.async { [weak self] in
                guard let self, !self.isPopupShowing else { return }
                self.presentedAlert = Utility.showAlert(title: Localization.optionalTitle, message: Localization.optionalMessage, defaultTitle: Localization.maybeLater, defaultHandler: handler, isCancel: true, cancelTitle: Localization.updateNow, cancelHandler: handler1)
                if self.presentedAlert != nil {
                    EventManager.shared.logEvent(title: AppUpdateKey.event_optional_update_home_pop_up_shown.rawValue)
                }
            }
            return true
        } else {
            return false
        }
    }
}
