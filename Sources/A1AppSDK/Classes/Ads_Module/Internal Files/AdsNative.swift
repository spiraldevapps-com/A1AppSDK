//
//  AdsNative.swift
//  A1IOSLib
//
//  Created by Mohammad Zaid on 28/11/23.
//

import GoogleMobileAds

protocol AdsNativeType: AnyObject {
    func load(from viewController: UIViewController,
              adUnitIdType: AdsAdUnitIdType,
              loaderOptions: AdsNativeAdLoaderOptions,
              adTypes: [GADAdLoaderAdType],
              onFinishLoading: (() -> Void)?,
              onError: ((Error) -> Void)?,
              onReceive: @escaping (GADNativeAd) -> Void)
    func stopLoading()
}

final class AdsNative: NSObject {

    // MARK: - Properties

    private let adUnitId: String
    private let request: () -> GADRequest

    private var onFinishLoading: (() -> Void)?
    private var onError: ((Error) -> Void)?
    private var onReceive: ((GADNativeAd) -> Void)?
    
    private var adLoader: GADAdLoader?
    
    // MARK: - Initialization

    init(adUnitId: String, request: @escaping () -> GADRequest) {
        self.adUnitId = adUnitId
        self.request = request
    }
}

// MARK: - AdsNativeType

extension AdsNative: AdsNativeType {
    func load(from viewController: UIViewController,
              adUnitIdType: AdsAdUnitIdType,
              loaderOptions: AdsNativeAdLoaderOptions,
              adTypes: [GADAdLoaderAdType],
              onFinishLoading: (() -> Void)?,
              onError: ((Error) -> Void)?,
              onReceive: @escaping (GADNativeAd) -> Void) {
        self.onFinishLoading = onFinishLoading
        self.onError = onError
        self.onReceive = onReceive

        // If AdLoader is already loading we should not make another request
        if let adLoader = adLoader, adLoader.isLoading { return }

        // Create multiple ads ad loader options
        var multipleAdsAdLoaderOptions: [GADMultipleAdsAdLoaderOptions]? {
            switch loaderOptions {
            case .single:
                return nil
            case .multiple(let numberOfAds):
                let options = GADMultipleAdsAdLoaderOptions()
                options.numberOfAds = numberOfAds
                return [options]
            }
        }

        // Set the ad unit id
        var adUnitId: String {
            return self.adUnitId
        }

        // Create GADAdLoader
        adLoader = GADAdLoader(
            adUnitID: adUnitId,
            rootViewController: viewController,
            adTypes: adTypes,
            options: multipleAdsAdLoaderOptions
        )

        // Set the GADAdLoader delegate
        adLoader?.delegate = self

        // Load ad with request
        adLoader?.load(request())
    }

    func stopLoading() {
        adLoader?.delegate = nil
        adLoader = nil
    }
}

// MARK: - GADNativeAdLoaderDelegate

extension AdsNative: GADNativeAdLoaderDelegate {
    func adLoader(_ adLoader: GADAdLoader, didReceive nativeAd: GADNativeAd) {
        onReceive?(nativeAd)
    }

    func adLoaderDidFinishLoading(_ adLoader: GADAdLoader) {
        onFinishLoading?()
    }

    func adLoader(_ adLoader: GADAdLoader, didFailToReceiveAdWithError error: Error) {
        onError?(error)
    }
}
