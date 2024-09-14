//
//  Utility.swift
//  A1IOSLib
//
//  Created by Navnidhi Sharma on 22/01/24.
//

import UIKit

class Utility {
    class func showAlert(title:String = Localization.alertTitle, message: String, defaultTitle: String? = Localization.okTitle, defaultHandler: ((UIAlertAction) -> Void)? = nil, isCancel: Bool = false, cancelTitle: String? = Localization.cancelTitle, cancelHandler: ((UIAlertAction) -> Void)? = nil) {
        let alert = UIAlertController(title: title, message: message, preferredStyle: UIAlertController.Style.alert)
        alert.addAction(UIAlertAction(title: defaultTitle, style: UIAlertAction.Style.default, handler: defaultHandler))
        if isCancel {
            alert.addAction(UIAlertAction(title: cancelTitle, style: UIAlertAction.Style.cancel, handler: cancelHandler))
        }
        
        let alertWindow = UIWindow(frame: UIScreen.main.bounds)
        alertWindow.rootViewController = UIViewController()
        alertWindow.windowLevel = UIWindow.Level.alert + 1;
        
        if let keyWindow = UIApplication.shared.windows.first,
           let rootViewController = keyWindow.rootViewController {
            rootViewController.present(alert, animated: true, completion: nil)
        }
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
