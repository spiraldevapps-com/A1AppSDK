//
//  Ads.swift
//  A1IOSLib
//
//  Created by Mohammad Zaid on 28/11/23.
//

import GoogleMobileAds

/**
 Ads
 
 A concret class implementation of AdsType to display ads from Google AdMob.
 */
public final class Ads: NSObject {

    // MARK: - Static Properties

    /// The shared Ads instance.
    public static let shared = Ads()

    // MARK: - Properties
    
    private let mobileAds: GADMobileAds

    private var configuration: AdsConfiguration?
    private var requestBuilder: AdsRequestBuilderType?
    private var appOpenAd: AdsAppOpenType?
    private var interstitialAd: AdsInterstitialType?
    private var rewardedAd: AdsRewardedType?
    private var rewardedInterstitialAd: AdsRewardedInterstitialType?
    private var nativeAd: AdsNativeType?
    private var disabled = false
    
    // MARK: - Initialization
    
    private override init() {
        mobileAds = .sharedInstance()
        super.init()
        
    }
}

// MARK: - AdsType

extension Ads: AdsType {
    public var isAppOpenAdSplashShowing: Bool {
        get {
            appOpenAd?.isAppOpenSplash ?? false
        }
        set {
            appOpenAd?.isAppOpenSplash = newValue
        }
    }
    
    /// Check if app open  ad is ready to be displayed.
    public var isAppOpenAdReady: Bool {
        appOpenAd?.isReady ?? false
    }
     
    /// Check if app open  ad is ready to be displayed.
    public var isAppOpenAdShowing: Bool {
        appOpenAd?.isShowing ?? false
    }

    public var isAppOpenAdLoading: Bool {
        appOpenAd?.isLoading ?? false
    }

    /// Check if interstitial ad is ready to be displayed.
    public var isInterstitialAdReady: Bool {
        interstitialAd?.isReady ?? false
    }
    
    /// Check if app open  ad is ready to be displayed.
    public var isInterAdShowing: Bool {
        interstitialAd?.isShowing ?? false
    }
     
    /// Check if rewarded ad is ready to be displayed.
    public var isRewardedAdReady: Bool {
        rewardedAd?.isReady ?? false
    }

    public var isRewardedAdShowing: Bool {
        rewardedAd?.isShowing ?? false
    }

    /// Check if rewarded interstitial ad is ready to be displayed.
    public var isRewardedInterstitialAdReady: Bool {
        rewardedInterstitialAd?.isReady ?? false
    }

    public var isRewardedInterstitialAdShowing: Bool {
        rewardedInterstitialAd?.isShowing ?? false
    }

    /// Returns true if ads have been disabled.
    public var isDisabled: Bool {
        disabled
    }
    
    public var getConfiguration: AdsConfiguration? {
        configuration
    }

    // MARK: Configure
    
    /// Configure Ads
    ///
    /// - parameter viewController: The view controller that will present the consent alert if needed.
    /// - parameter requestBuilder: The GADRequest builder.
    /// - parameter mediationConfigurator: Optional configurator to update mediation networks COPPA/GDPR consent status.
    /// - parameter consentStatusDidChange: A handler that will be called everytime the consent status has changed.
    /// - parameter completion: A completion handler that will return the current consent status after the initial consent flow has finished.
    ///
    /// - Warning:
    /// Returns .notRequired in the completion handler if consent has been disabled via Ads.plist isUMPDisabled entry.
    public func configure(from adConfig: AdsConfiguration,
                          requestBuilder: AdsRequestBuilderType
                          ) {
        let configuration: AdsConfiguration
        configuration = adConfig
        self.configuration = configuration
        self.requestBuilder = requestBuilder

         // Create ads
        let appOpenAdUnitId = configuration.appOpenID
        if appOpenAdUnitId != "" {
            let appOpenAdUnitId = configuration.appOpenID
            appOpenAd = AppOpenAdManager(
                adUnitId: appOpenAdUnitId,
                request: requestBuilder.build
            )
        }
        let interstitialAdUnitId = configuration.interID
        if interstitialAdUnitId != "" {
            interstitialAd = AdsInterstitial(
                adUnitId: interstitialAdUnitId,
                request: requestBuilder.build
            )
        }
        let rewardedInterstitialAdUnitId = configuration.rewardedInterstitialID
        if rewardedInterstitialAdUnitId != "" {
            rewardedInterstitialAd = AdsRewardedInterstitial(
                adUnitId: rewardedInterstitialAdUnitId,
                request: requestBuilder.build
            )
        }
        let nativeAdUnitId = configuration.nativeID
        if nativeAdUnitId != "" {
            nativeAd = AdsNative(
                adUnitId: nativeAdUnitId,
                request: requestBuilder.build
            )
        }

        // If UMP SDK is disabled skip consent flow completely
//        if let isUMPDisabled = configuration.isUMPDisabled, isUMPDisabled {
//            /// If consent flow was skipped we need to update COPPA settings.
//            updateCOPPA(for: configuration, mediationConfigurator: mediationConfigurator)
//
//            /// If consent flow was skipped we can start `GADMobileAds` and preload ads.
            startMobileAdsSDK { [weak self] in
                guard let self = self else { return }
                self.loadAds()
            }
    }
    
    public func configureRewardedAds() {
        let rewardedAdUnitId = configuration?.rewardedID
        if let rewardedAdUnitId = rewardedAdUnitId, let requestBuilder =  self.requestBuilder {
            rewardedAd = AdsRewarded(
                adUnitId: rewardedAdUnitId,
                request: requestBuilder.build
            )
            rewardedAd?.load()
        }
    }

    // MARK: Banner Ads
    
    /// Make banner ad
    ///
    /// - parameter viewController: The view controller that will present the ad.
    /// - parameter adUnitIdType: The adUnitId type for the ad, either plist or custom.
    /// - parameter position: The position of the banner.
    /// - parameter animation: The animation of the banner.
    /// - parameter onOpen: An optional callback when the banner was presented.
    /// - parameter onClose: An optional callback when the banner was dismissed or removed.
    /// - parameter onError: An optional callback when an error has occurred.
    /// - parameter onWillPresentScreen: An optional callback when the banner was tapped and is about to present a screen.
    /// - parameter onWillDismissScreen: An optional callback when the banner is about dismiss a presented screen.
    /// - parameter onDidDismissScreen: An optional callback when the banner did dismiss a presented screen.
    /// - returns AdsBannerType to show, hide or remove the prepared banner ad.
    public func makeBannerAd(in viewController: UIViewController,
                             onOpen: (() -> Void)?,
                             onClose: (() -> Void)?,
                             onError: ((Error) -> Void)?,
                             onWillPresentScreen: (() -> Void)?,
                             onWillDismissScreen: (() -> Void)?,
                             onDidDismissScreen: (() -> Void)?) -> (AdsBannerType, UIView)? {
        guard !isDisabled else { return nil }

        var adUnitId: String? {
            configuration?.bannerID
        }

        guard let validAdUnitId = adUnitId else {
            onError?(AdsError.bannerAdMissingAdUnitId)
            return nil
        }

        let bannerAd = AdsBanner(
            isDisabled: { [weak self] in
                self?.isDisabled ?? false
            },
            request: { [weak self] in
                self?.requestBuilder?.build() ?? GADRequest()
            }
        )
        EventManager.shared.logEvent(title: AdsKey.event_ad_banner_load_start.rawValue)
        let gadBannerView = bannerAd.prepare(
            withAdUnitId: validAdUnitId,
            in: viewController,
            onOpen: onOpen,
            onClose: onClose,
            onError: onError,
            onWillPresentScreen: onWillPresentScreen,
            onWillDismissScreen: onWillDismissScreen,
            onDidDismissScreen: onDidDismissScreen
        )
        EventManager.shared.logEvent(title: AdsKey.event_ad_banner_loaded.rawValue)
        return (bannerAd, gadBannerView)
    }
    
    // MARK: App Open Ads
    
    public func showAppOpenAd(from viewController: UIViewController, onOpen: (() -> Void)?, onClose: (() -> Void)?, onError: ((Error) -> Void)?) {
        appOpenAd?.show(from: viewController,
                        onOpen: onOpen,
                        onClose: onClose,
                        onError: onError
        )
    }

    // MARK: Interstitial Ads
    
//    / Show interstitial ad
    /// - parameter viewController: The view controller that will present the ad.
    /// - parameter onOpen: An optional callback when the ad was presented.
    /// - parameter onClose: An optional callback when the ad was dismissed.
    /// - parameter onError: An optional callback when an error has occurred.
    public func showInterstitialAd(from viewController: UIViewController,
                                   onOpen: (() -> Void)?,
                                   onClose: (() -> Void)?,
                                   onError: ((Error) -> Void)?) {
        guard !isDisabled else { return }
        
        interstitialAd?.show(
            from: viewController,
            onOpen: onOpen,
            onClose: onClose,
            onError: onError
        )
    }

    // MARK: Rewarded Ads
    
    /// Show rewarded ad
    ///
    /// - parameter viewController: The view controller that will present the ad.
    /// - parameter onOpen: An optional callback when the ad was presented.
    /// - parameter onClose: An optional callback when the ad was dismissed.
    /// - parameter onError: An optional callback when an error has occurred.
    /// - parameter onNotReady: An optional callback when the ad was not ready.
    /// - parameter onReward: A callback when the reward has been granted.
    ///
    /// - Warning:
    /// Rewarded ads may be non-skippable and should only be displayed after pressing a dedicated button.
    public func showRewardedAd(from viewController: UIViewController,
                               onOpen: (() -> Void)?,
                               onClose: (() -> Void)?,
                               onError: ((Error) -> Void)?,
                               onNotReady: (() -> Void)?,
                               onReward: @escaping (NSDecimalNumber) -> Void) {
//        guard hasConsent else { return }

        rewardedAd?.show(
            from: viewController,
            onOpen: onOpen,
            onClose: onClose,
            onError: onError,
            onNotReady: onNotReady,
            onReward: onReward
        )
    }

    /// Show rewarded interstitial ad
    ///
    /// - parameter viewController: The view controller that will present the ad.
    /// - parameter onOpen: An optional callback when the ad was presented.
    /// - parameter onClose: An optional callback when the ad was dismissed.
    /// - parameter onError: An optional callback when an error has occurred.
    /// - parameter onReward: A callback when the reward has been granted.
    ///
    /// - Warning:
    /// Before displaying a rewarded interstitial ad to users, you must present the user with an intro screen that provides clear reward messaging
    /// and an option to skip the ad before it starts.
    /// https://support.google.com/admob/answer/9884467
    public func showRewardedInterstitialAd(from viewController: UIViewController,
                                           onOpen: (() -> Void)?,
                                           onClose: (() -> Void)?,
                                           onError: ((Error) -> Void)?,
                                           onReward: @escaping (NSDecimalNumber) -> Void) {
        guard !isDisabled else { return }

        rewardedInterstitialAd?.show(
            from: viewController,
            onOpen: onOpen,
            onClose: onClose,
            onError: onError,
            onReward: onReward
        )
    }

    // MARK: Native Ads

    /// Load native ad
    ///
    /// - parameter viewController: The view controller that will load the native ad.
    /// - parameter adUnitIdType: The adUnitId type for the ad, either plist or custom.
    /// - parameter loaderOptions: The loader options for GADMultipleAdsAdLoaderOptions, single or multiple.
    /// - parameter onFinishLoading: An optional callback when the load request has finished.
    /// - parameter onError: An optional callback when an error has occurred.
    /// - parameter onReceive: A callback when the GADNativeAd has been received.
    ///
    /// - Warning:
    /// Requests for multiple native ads don't currently work for AdMob ad unit IDs that have been configured for mediation.
    /// Publishers using mediation should avoid using the GADMultipleAdsAdLoaderOptions class when making requests i.e. set loaderOptions parameter to .single.
    public func loadNativeAd(from viewController: UIViewController,
                             adUnitIdType: AdsAdUnitIdType,
                             loaderOptions: AdsNativeAdLoaderOptions,
                             onFinishLoading: (() -> Void)?,
                             onError: ((Error) -> Void)?,
                             onReceive: @escaping (GADNativeAd) -> Void) {
        guard !isDisabled else { return }

        if nativeAd == nil, case .custom(let adUnitId) = adUnitIdType {
            nativeAd = AdsNative(
                adUnitId: adUnitId,
                request: { [weak self] in
                    self?.requestBuilder?.build() ?? GADRequest()
                }
            )
        }

        nativeAd?.load(
            from: viewController,
            adUnitIdType: adUnitIdType,
            loaderOptions: loaderOptions,
            adTypes: [.native],
            onFinishLoading: onFinishLoading,
            onError: onError,
            onReceive: onReceive
        )
    }

    // MARK: Enable/Disable

    /// Enable/Disable ads
    ///
    /// - parameter isDisabled: Set to true to disable ads or false to enable ads.
    public func setDisabled(_ isDisabled: Bool) {
        disabled = isDisabled
        if isDisabled {
            interstitialAd?.stopLoading()
            rewardedInterstitialAd?.stopLoading()
            nativeAd?.stopLoading()
            appOpenAd?.stopLoading()
        } else {
            loadAds()
        }
    }
}

// MARK: - Private Methods

private extension Ads {
    
    func startMobileAdsSDK(completion: @escaping () -> Void) {
        /*
         Warning:
         Ads may be preloaded by the Mobile Ads SDK or mediation partner SDKs upon
         calling startWithCompletionHandler:. If you need to obtain consent from users
         in the European Economic Area (EEA), set any request-specific flags (such as
         tagForChildDirectedTreatment or tag_for_under_age_of_consent), or otherwise
         take action before loading ads, ensure you do so before initializing the Mobile
         Ads SDK.
        */
        mobileAds.start { initializationStatus in
            print("Ads initialization status", initializationStatus.adapterStatusesByClassName)
            completion()
        }
    }
    
    func loadAds() {
        guard !isDisabled else { return }
        appOpenAd?.load()
        interstitialAd?.load()
        rewardedAd?.load()
        rewardedInterstitialAd?.load()
    }
}

