import Foundation
import AppTrackingTransparency
import AdSupport

public enum TrackingPersmissionStatus: String {
    case authorized
    case denied
    case notDetermined
    case unknown
}

@available(iOS 14, *)
public class TrackingViewModel {
    var trackingModelStatus: TrackingPersmissionStatus = .notDetermined
    var trackingManagerStatus: ATTrackingManager.AuthorizationStatus {
        return ATTrackingManager.trackingAuthorizationStatus
    }
    public init() {
        updateCurrentStatus()
    }
    
    public func updateCurrentStatus()  {
        let status = ATTrackingManager.trackingAuthorizationStatus
        switch status {
        case .authorized:
            // racking authorization dialog was shown and we are authorized
            print("Authorized")
            trackingModelStatus = .authorized
        case .denied:
            // Tracking authorization dialog was shown and permission is denied
            print("Denied")
            trackingModelStatus = .denied
        case .notDetermined:
            // Tracking authorization dialog has not been shown
            print("Not Determined")
            trackingModelStatus = .notDetermined
        case .restricted:
            print("Restricted")
            trackingModelStatus = .denied
        @unknown default:
            print("Unknown")
            trackingModelStatus = .unknown
        }
    }

    public func shouldShowAppTrackingDialog() -> Bool {
        let status = ATTrackingManager.trackingAuthorizationStatus
        guard status != .notDetermined else {
            return true
        }
        return false
    }
    
    func isAuthorized() -> Bool {
        return trackingManagerStatus == .authorized
    }
    
    func requestPermission() {
        ATTrackingManager.requestTrackingAuthorization { status in
            switch status {
            case .authorized:
                // Tracking authorization dialog was shown and we are authorized
                print("Authorized")
                print("IDFA", self.getIDFA())
            case .denied:
                // Tracking authorization dialog was shown and permission is denied
                print("Denied")
            case .notDetermined:
                // Tracking authorization dialog has not been shown
                print("Not Determined")
            case .restricted:
                print("Restricted")
            @unknown default:
                print("Unknown")
            }
        }
    }
    
    public func getIDFA() -> UUID {
        return ASIdentifierManager.shared().advertisingIdentifier
    }
    
    func provideIdentifierForAdvertisingIfAvailable() -> UUID? {
        if ASIdentifierManager.shared().isAdvertisingTrackingEnabled {
            return ASIdentifierManager.shared().advertisingIdentifier
        } else {
          return nil
        }
      }

    public func requestAppTrackingPermission(_ completion: @escaping (ATTrackingManager.AuthorizationStatus) -> Void) {
        ATTrackingManager.requestTrackingAuthorization(completionHandler: completion)
    }
}
