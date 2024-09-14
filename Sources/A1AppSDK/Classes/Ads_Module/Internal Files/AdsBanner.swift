//
//  AdsBanner.swift
//  A1IOSLib
//
//  Created by Mohammad Zaid on 28/11/23.
//
import GoogleMobileAds
import ShimmerSwift

final class AdsBanner: NSObject {
    
    // MARK: - Properties

    private let isDisabled: () -> Bool
    private let request: () -> GADRequest

    private var onOpen: (() -> Void)?
    private var onClose: (() -> Void)?
    private var onError: ((Error) -> Void)?
    private var onWillPresentScreen: (() -> Void)?
    private var onWillDismissScreen: (() -> Void)?
    private var onDidDismissScreen: (() -> Void)?

    private var bannerView: GADBannerView?
    private var shimmer: ShimmeringView = ShimmeringView()
    private var shimmerContentView: UIView = UIView()
    private var bannerContainer: UIView = UIView()
    
    // MARK: - Initialization
    
    init(isDisabled: @escaping () -> Bool,
         request: @escaping () -> GADRequest) {
        self.isDisabled = isDisabled
        self.request = request
        super.init()
    }

    // MARK: - Convenience
    
    func prepare(withAdUnitId adUnitId: String,
                 in viewController: UIViewController,
                 onOpen: (() -> Void)?,
                 onClose: (() -> Void)?,
                 onError: ((Error) -> Void)?,
                 onWillPresentScreen: (() -> Void)?,
                 onWillDismissScreen: (() -> Void)?,
                 onDidDismissScreen: (() -> Void)?) -> UIView {
        self.onOpen = onOpen
        self.onClose = onClose
        self.onError = onError
        self.onWillPresentScreen = onWillPresentScreen
        self.onWillDismissScreen = onWillDismissScreen
        self.onDidDismissScreen = onDidDismissScreen
        // Create banner view
        let bannerView = GADBannerView()
        bannerView.frame = CGRect(x: 0, y: 0, width: UIScreen.main.bounds.width, height: 60)

        // Keep reference to created banner view
        self.bannerView = bannerView

        // Set ad unit id
        bannerView.adUnitID = adUnitId

        // Set the root view controller that will display the banner view
        bannerView.rootViewController = viewController

        // Set the banner view delegate
        bannerView.delegate = self
        bannerContainer = UIView()
        bannerContainer.frame = bannerView.frame
        shimmer = ShimmeringView()
        shimmer.shimmerSpeed = 400
        shimmer.frame = bannerView.frame
        bannerContainer.addSubview(shimmer)
        shimmerContentView = UIView(frame: shimmer.bounds)
        shimmerContentView.backgroundColor = .lightGray
        // Add the view you want shimmered to the `shimmerView`
        shimmer.contentView = shimmerContentView
        // Start shimmering
        shimmer.isShimmering = true
        bannerContainer.addSubview(bannerView)
        return bannerContainer
    }
}

// MARK: - AdsBannerType

extension AdsBanner: AdsBannerType {
    func show() {
        EventManager.shared.logEvent(title: AdsKey.event_ad_banner_shown.rawValue)
        guard !isDisabled() else { return }
        guard let bannerView = bannerView else { return }
        bannerView.adSize = GADPortraitAnchoredAdaptiveBannerAdSizeWithWidth(UIScreen.main.bounds.width)
        bannerView.load(request())
    }
    
    func remove() {
        guard bannerView != nil else { return }
        
        bannerView?.delegate = nil
        bannerView?.removeFromSuperview()
        bannerView = nil
        onClose?()
    }
    
    func updateLayout() {
        shimmer.isHidden = false
        shimmer.isShimmering = true
        if let banner = bannerView {
            banner.frame.size.width = UIScreen.main.bounds.width
            bannerContainer.frame.size.width = UIScreen.main.bounds.width
            shimmer.frame.size.width = UIScreen.main.bounds.width
            shimmerContentView.frame.size.width = UIScreen.main.bounds.width
        }
    }
}

// MARK: - GADBannerViewDelegate

extension AdsBanner: GADBannerViewDelegate {
    // Request lifecycle events
    func bannerViewDidRecordImpression(_ bannerView: GADBannerView) {
        print("AdsBanner did record impression for banner ad")
    }
    
    func bannerViewDidReceiveAd(_ bannerView: GADBannerView) {
        onOpen?()
        shimmer.isHidden = true
        print("AdsBanner did receive ad from: \(bannerView.responseInfo?.loadedAdNetworkResponseInfo?.adNetworkClassName ?? "not found")")
    }

    func bannerView(_ bannerView: GADBannerView, didFailToReceiveAdWithError error: Error) {
        EventManager.shared.logEvent(title: AdsKey.event_ad_banner_load_failed.rawValue)
        EventManager.shared.logEvent(title: AppErrorKey.event_ad_error_load_failed.rawValue, key: "error", value: error.localizedDescription)
        onError?(error)
        shimmer.isHidden = true
    }

    // Click-Time lifecycle events
    func bannerViewWillPresentScreen(_ bannerView: GADBannerView) {
        EventManager.shared.logEvent(title: AdsKey.event_ad_banner_show_requested.rawValue)
        onWillPresentScreen?()
    }

    func bannerViewWillDismissScreen(_ bannerView: GADBannerView) {
        onWillDismissScreen?()
    }

    func bannerViewDidDismissScreen(_ bannerView: GADBannerView) {
        onDidDismissScreen?()
    }
}
