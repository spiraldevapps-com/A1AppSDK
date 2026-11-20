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
            sdkDebugPrint("Authorized")
            trackingModelStatus = .authorized
        case .denied:
            // Tracking authorization dialog was shown and permission is denied
            sdkDebugPrint("Denied")
            trackingModelStatus = .denied
        case .notDetermined:
            // Tracking authorization dialog has not been shown
            sdkDebugPrint("Not Determined")
            trackingModelStatus = .notDetermined
        case .restricted:
            sdkDebugPrint("Restricted")
            trackingModelStatus = .denied
        @unknown default:
            sdkDebugPrint("Unknown")
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
                sdkDebugPrint("Authorized")
                sdkDebugPrint("IDFA \(self.getIDFA())")
            case .denied:
                // Tracking authorization dialog was shown and permission is denied
                sdkDebugPrint("Denied")
            case .notDetermined:
                // Tracking authorization dialog has not been shown
                sdkDebugPrint("Not Determined")
            case .restricted:
                sdkDebugPrint("Restricted")
            @unknown default:
                sdkDebugPrint("Unknown")
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
