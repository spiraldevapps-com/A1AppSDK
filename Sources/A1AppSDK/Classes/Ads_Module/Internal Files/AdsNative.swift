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

        let options: [GADMultipleAdsAdLoaderOptions]?
        switch loaderOptions {
        case .single:
            options = nil
        case .multiple(let numberOfAds):
            let multipleAds = GADMultipleAdsAdLoaderOptions()
            multipleAds.numberOfAds = numberOfAds
            options = [multipleAds]
        }

        let loader = GADAdLoader(
            adUnitID: adUnitId,
            rootViewController: viewController,
            adTypes: adTypes,
            options: options
        )
        adLoader = loader
        loader.delegate = self
        loader.load(request())
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
