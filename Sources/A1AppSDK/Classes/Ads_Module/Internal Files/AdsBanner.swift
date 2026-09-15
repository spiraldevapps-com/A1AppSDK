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
    private let shimmer = ShimmeringView()
    private let shimmerContentView = UIView()
    private let bannerContainer = UIView()
    
    // MARK: - Initialization
    
    init(isDisabled: @escaping () -> Bool,
         request: @escaping () -> GADRequest) {
        self.isDisabled = isDisabled
        self.request = request
        super.init()
    }

    /// Console diagnostics only. Compiled out of release builds, so the message is never built.
    private func debugLog(_ message: @autoclosure () -> String) {
        #if DEBUG
        print(message())
        #endif
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

        let frame = CGRect(x: 0, y: 0, width: UIScreen.main.bounds.width, height: 60)
        let bannerView = GADBannerView()
        bannerView.frame = frame
        self.bannerView = bannerView
        bannerView.adUnitID = adUnitId
        bannerView.rootViewController = viewController
        bannerView.delegate = self

        bannerContainer.frame = frame
        shimmer.shimmerSpeed = 400
        shimmer.frame = frame
        bannerContainer.addSubview(shimmer)
        shimmerContentView.frame = shimmer.bounds
        shimmerContentView.backgroundColor = .lightGray
        // Add the view you want shimmered to the `shimmerView`
        shimmer.contentView = shimmerContentView
        shimmer.isShimmering = true
        bannerContainer.addSubview(bannerView)
        return bannerContainer
    }
}

// MARK: - AdsBannerType

extension AdsBanner: AdsBannerType {
    func show() {
        EventManager.shared.logEvent(title: AdsKey.event_ad_banner_shown.rawValue)
        guard !isDisabled(), let bannerView = bannerView else { return }
        bannerView.adSize = GADPortraitAnchoredAdaptiveBannerAdSizeWithWidth(UIScreen.main.bounds.width)
        bannerView.load(request())
    }
    
    func remove() {
        guard let bannerView = bannerView else { return }

        bannerView.delegate = nil
        bannerView.removeFromSuperview()
        self.bannerView = nil
        onClose?()
    }
    
    func updateLayout() {
        shimmer.isHidden = false
        shimmer.isShimmering = true
        guard let bannerView = bannerView else { return }
        let width = UIScreen.main.bounds.width
        bannerView.frame.size.width = width
        bannerContainer.frame.size.width = width
        shimmer.frame.size.width = width
        shimmerContentView.frame.size.width = width
    }
}

// MARK: - GADBannerViewDelegate

extension AdsBanner: GADBannerViewDelegate {
    // Request lifecycle events
    func bannerViewDidRecordImpression(_ bannerView: GADBannerView) {
        debugLog("AdsBanner did record impression for banner ad")
    }
    
    func bannerViewDidReceiveAd(_ bannerView: GADBannerView) {
        onOpen?()
        shimmer.isHidden = true
        debugLog("AdsBanner did receive ad from: \(bannerView.responseInfo?.loadedAdNetworkResponseInfo?.adNetworkClassName ?? "not found")")
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
