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
              adTypes: [AdLoaderAdType],
              onFinishLoading: (() -> Void)?,
              onError: ((Error) -> Void)?,
              onReceive: @escaping (NativeAd) -> Void)
    func stopLoading()
}

final class AdsNative: NSObject {

    // MARK: - Properties

    private let adUnitId: String
    private let request: () -> Request

    private var onFinishLoading: (() -> Void)?
    private var onError: ((Error) -> Void)?
    private var onReceive: ((NativeAd) -> Void)?
    
    private var adLoader: AdLoader?
    
    // MARK: - Initialization

    init(adUnitId: String, request: @escaping () -> Request) {
        self.adUnitId = adUnitId
        self.request = request
    }
}

// MARK: - AdsNativeType

extension AdsNative: AdsNativeType {
    func load(from viewController: UIViewController,
              adUnitIdType: AdsAdUnitIdType,
              loaderOptions: AdsNativeAdLoaderOptions,
              adTypes: [AdLoaderAdType],
              onFinishLoading: (() -> Void)?,
              onError: ((Error) -> Void)?,
              onReceive: @escaping (NativeAd) -> Void) {
        self.onFinishLoading = onFinishLoading
        self.onError = onError
        self.onReceive = onReceive

        // If AdLoader is already loading we should not make another request
        if let adLoader = adLoader, adLoader.isLoading { return }

        // Create multiple ads ad loader options
        var multipleAdsAdLoaderOptions: [MultipleAdsAdLoaderOptions]? {
            switch loaderOptions {
            case .single:
                return nil
            case .multiple(let numberOfAds):
                let options = MultipleAdsAdLoaderOptions()
                options.numberOfAds = numberOfAds
                return [options]
            }
        }

        // Set the ad unit id
        var adUnitId: String {
            return self.adUnitId
        }

        // Create AdLoader
        adLoader = AdLoader(
            adUnitID: adUnitId,
            rootViewController: viewController,
            adTypes: adTypes,
            options: multipleAdsAdLoaderOptions
        )

        // Set the AdLoader delegate
        adLoader?.delegate = self

        // Load ad with request
        adLoader?.load(request())
    }

    func stopLoading() {
        adLoader?.delegate = nil
        adLoader = nil
    }
}

// MARK: - NativeAdLoaderDelegate

extension AdsNative: NativeAdLoaderDelegate {
    func adLoader(_ adLoader: AdLoader, didReceive nativeAd: NativeAd) {
        onReceive?(nativeAd)
    }

    func adLoaderDidFinishLoading(_ adLoader: AdLoader) {
        onFinishLoading?()
    }

    func adLoader(_ adLoader: AdLoader, didFailToReceiveAdWithError error: Error) {
        onError?(error)
    }
}
