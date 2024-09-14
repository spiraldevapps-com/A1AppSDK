//
//  DebugViewController.swift
//  A1IOSLib_Example
//
//  Created by Navnidhi Sharma on 27/12/23.
//  Copyright © 2023 CocoaPods. All rights reserved.
//

import UIKit

extension Bundle {
    var applicationName: String {

        if let displayName: String = self.infoDictionary?["CFBundleDisplayName"] as? String {
            return displayName
        } else if let name: String = self.infoDictionary?["CFBundleName"] as? String {
            return name
        }
        return "No Name Found"
    }
    
    public var shortVersion: String {
        if let result = infoDictionary?["CFBundleShortVersionString"] as? String {
            return result
        } else {
            assert(false)
            return ""
        }
    }

    public var buildVersion: String {
        if let result = infoDictionary?["CFBundleVersion"] as? String {
            return result
        } else {
            assert(false)
            return ""
        }
    }

    public var fullVersion: String {
        return "\(shortVersion)(\(buildVersion))"
    }
}

public class DebugViewController: UIViewController {
    @IBOutlet weak var versionLabel: UILabel!
    @IBOutlet weak var adsFlagLabel: UILabel!
    
    public override func viewDidLoad() {
        super.viewDidLoad()
        let name = Bundle.main.applicationName
        let version = Bundle.main.fullVersion
        guard versionLabel != nil, adsFlagLabel != nil else { return }
#if DEBUG
    print("I'm running in DEBUG mode")
        versionLabel.text = "Version Name = \(name)-\(version)-internal"
#else
    print("I'm running in a non-DEBUG mode")
        versionLabel.text = "Version Name = \(name)-\(version)-production"
#endif
        if Ads.shared.isDisabled == true {
            adsFlagLabel.text = "false"
        } else {
            adsFlagLabel.text = "true"
        }
        // Do any additional setup after loading the view.
    }
    
    @IBAction func adsAction(_ sender: Any) {
        let storyboard = UIStoryboard(name: "Debug", bundle: nil)
        if let vc = storyboard.instantiateViewController(withIdentifier: "DebugAdsViewController") as? DebugAdsViewController {
            navigationController?.pushViewController(vc, animated: true)
        }
    }
    
    struct Constants {
        static let reuseIdentifier = String(describing: DebugViewController.self)
        static let storyboardName = "Debug"
    }
    
    public static func buildViewController() -> DebugViewController {
        if let controller = UIStoryboard(name: Constants.storyboardName,
                                         bundle: .main).instantiateViewController(withIdentifier: Constants.reuseIdentifier) as? DebugViewController {
            return controller
        }
        return DebugViewController()
    }
}
