//
//  Utility.swift
//  A1IOSLib
//
//  Created by Navnidhi Sharma on 22/01/24.
//

import UIKit

class Utility {
    /// Presents on the top-most controller of the foreground key window: an alert has to sit
    /// above a paywall or sheet, not be refused by a root that is already presenting. Never
    /// stacks on another alert. Returns the alert when it is on screen and nil otherwise, so
    /// a caller can track the alert itself instead of latching a flag that might be wrong.
    @discardableResult
    class func showAlert(title:String = Localization.alertTitle, message: String, defaultTitle: String? = Localization.okTitle, defaultHandler: ((UIAlertAction) -> Void)? = nil, isCancel: Bool = false, cancelTitle: String? = Localization.cancelTitle, cancelHandler: ((UIAlertAction) -> Void)? = nil) -> UIAlertController? {
        let alert = UIAlertController(title: title, message: message, preferredStyle: UIAlertController.Style.alert)
        alert.addAction(UIAlertAction(title: defaultTitle, style: UIAlertAction.Style.default, handler: defaultHandler))
        if isCancel {
            alert.addAction(UIAlertAction(title: cancelTitle, style: UIAlertAction.Style.cancel, handler: cancelHandler))
        }

        guard let presenter = topMostViewController(),
              !(presenter is UIAlertController),
              presenter.presentedViewController == nil,
              !presenter.isBeingDismissed, !presenter.isBeingPresented else { return nil }
        presenter.present(alert, animated: true, completion: nil)
        return alert
    }

    /// The controller at the top of the foreground key window's presentation chain, or nil
    /// before a window exists. Background scenes are skipped: on iPad with two windows the
    /// alert must land in the one the user is looking at.
    class func topMostViewController() -> UIViewController? {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let foreground = scenes.filter { $0.activationState == .foregroundActive || $0.activationState == .foregroundInactive }
        let windows = (foreground.isEmpty ? scenes : foreground).flatMap(\.windows)
        guard var top = (windows.first { $0.isKeyWindow } ?? windows.first)?.rootViewController else { return nil }
        while let presented = top.presentedViewController, !presented.isBeingDismissed { top = presented }
        return top
    }
    
    /// Opens applications app store URL
    class func openAppStore(urlString: String) {
        if let url = URL(string: urlString),
           UIApplication.shared.canOpenURL(url) {
            UIApplication.shared.open(url, options:
                                        convertToUIApplicationOpenExternalURLOptionsKeyDictionary([:])
                                      ,completionHandler: nil)
        }
        return
    }

}

// Helper function inserted by Swift 4.2 migrator.
func convertToUIApplicationOpenExternalURLOptionsKeyDictionary(_ input: [String: Any]) -> [UIApplication.OpenExternalURLOptionsKey: Any] {
    return Dictionary(uniqueKeysWithValues: input.map { key, value in (UIApplication.OpenExternalURLOptionsKey(rawValue: key), value)})
}
