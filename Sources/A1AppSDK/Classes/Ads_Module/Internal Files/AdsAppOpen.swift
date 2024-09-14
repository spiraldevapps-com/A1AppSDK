//
//  AdsAppOpen.swift
//  A1IOSLib
//
//  Created by Mohammad Zaid on 29/11/23.
//

import Foundation

import GoogleMobileAds

protocol AdsAppOpenType: AnyObject {
    var isAppOpenSplash: Bool { get set }
    var isReady: Bool { get }
    var isShowing: Bool { get }
    var isLoading: Bool { get }
    func load()
    func stopLoading()
    func show(from viewController: UIViewController,
              onOpen: (() -> Void)?,
              onClose: (() -> Void)?,
              onError: ((Error) -> Void)?)
}

final class AppOpenAdManager: NSObject {
    private let adUnitId: String
    private let request: () -> GADRequest

  /// The app open ad.
  private var appOpenAd: GADAppOpenAd?
  /// Maintains a reference to the delegate.
  /// Keeps track of if an app open ad is loading.
  var isLoadingAd = false
  /// Keeps track of if an app open ad is showing.
  var isShowingAd = false
  var isAppOpenAdSplash = false
  /// Keeps track of the time when an app open ad was loaded to discard expired ad.
    private var viewController: UIViewController?
    private var showAdAfterLoad = false

    private var onOpen: (() -> Void)?
    private var onClose: (() -> Void)?
    private var onError: ((Error) -> Void)?

  //static let shared = AppOpenAdManager()
    
    init(adUnitId: String, request: @escaping () -> GADRequest) {
        self.adUnitId = adUnitId
        self.request = request
    }

  private func isAdAvailable() -> Bool {
    // Check if ad exists and can be shown.
    return appOpenAd != nil
  }

  func loadAd() {
    // Do not load ad if there is an unused ad or one is already loading.
    if isLoadingAd || isAdAvailable() {
      return
    }
      EventManager.shared.logEvent(title: AdsKey.event_ad_appopen_load_start.rawValue)
    isLoadingAd = true
    print("Start loading app open ad.")
    GADAppOpenAd.load(withAdUnitID: adUnitId, request: request()) { [weak self] (ad, error) in
        guard let self else {return}
        self.isLoadingAd = false
      if let error = error {
        self.appOpenAd = nil
        print("App open ad failed to load with error: \(error.localizedDescription)")
          EventManager.shared.logEvent(title: AdsKey.event_ad_appopen_load_failed.rawValue)
          EventManager.shared.logEvent(title: AppErrorKey.event_ad_error_load_failed.rawValue, key: "error", value: error.localizedDescription)
          self.onError?(error)
        return
      }
        EventManager.shared.logEvent(title: AdsKey.event_ad_appopen_loaded.rawValue)
      self.appOpenAd = ad
      self.appOpenAd?.fullScreenContentDelegate = self
        print("App open ad loaded successfully.")
        if self.showAdAfterLoad, let ads = self.appOpenAd, let viewController = self.viewController {
            self.isShowingAd = true
            self.showAdAfterLoad = false
            ads.present(fromRootViewController: viewController)
            EventManager.shared.logEvent(title: AdsKey.event_ad_appopen_shown.rawValue)
            self.viewController = nil
        }
    }
  }

  func showAdIfAvailable(viewController: UIViewController,
                         onOpen: (() -> Void)?,
                         onClose: (() -> Void)?,
                         onError: ((Error) -> Void)?) {
      self.onOpen = onOpen
      self.onClose = onClose
      self.onError = onError
      self.viewController = viewController
      self.showAdAfterLoad = true
      EventManager.shared.logEvent(title: AdsKey.event_ad_appopen_show_requested.rawValue)
      
    // If the app open ad is already showing, do not show the ad again.
    if isShowingAd {
      print("App open ad is already showing.")
      return
    }
    // If the app open ad is not available yet but it is supposed to show,
    // it is considered to be complete in this example. Call the appOpenAdManagerAdDidComplete
    // method and load a new ad.
    if !isAdAvailable() {
      print("App open ad is not ready yet.")
      loadAd()
      return
    }
    if let ad = appOpenAd {
      print("App open ad will be displayed.")
      isShowingAd = true
    self.showAdAfterLoad = false
        EventManager.shared.logEvent(title: AdsKey.event_ad_appopen_shown.rawValue)
      ad.present(fromRootViewController: viewController)
    }
  }
}

// MARK: - GADFullScreenContentDelegate

extension AppOpenAdManager: GADFullScreenContentDelegate {
  func adWillPresentFullScreenContent(_ ad: GADFullScreenPresentingAd) {
    print("App open ad is will be presented.")
    onOpen?()
  }

  func adDidDismissFullScreenContent(_ ad: GADFullScreenPresentingAd) {
    appOpenAd = nil
    isShowingAd = false
    print("App open ad was dismissed.")
      // Send callback
      onClose?()
      AdsHandler.shared.appOpenLoadTime = Date()
      // Load the next ad so its ready for displaying
      loadAd()
  }

  func ad(
    _ ad: GADFullScreenPresentingAd,
    didFailToPresentFullScreenContentWithError error: Error
  ) {
      //appOpenAd = nil
      isShowingAd = false
      EventManager.shared.logEvent(title: AdsKey.event_ad_appopen_show_failed.rawValue)
      EventManager.shared.logEvent(title: AppErrorKey.event_ad_error_show_failed.rawValue, key: "error", value: error.localizedDescription)
      print("App open ad failed to present with error: \(error.localizedDescription)")
      if appOpenAd == nil {
          loadAd()
      }
      onError?(error)
  }
}

extension AppOpenAdManager: AdsAppOpenType {
    var isAppOpenSplash: Bool {
        get {
            return isAppOpenAdSplash
        }
        set {
            isAppOpenAdSplash = newValue
        }
    }
        
    var isReady: Bool {
        return isAdAvailable()
    }
    
    var isShowing: Bool {
        return isShowingAd
    }

    var isLoading: Bool {
        return isLoadingAd
    }

    func load() {
        loadAd()
    }
    
    func stopLoading() {
        appOpenAd?.fullScreenContentDelegate = nil
        appOpenAd = nil
    }
    
    func show(from viewController: UIViewController, onOpen: (() -> Void)?, onClose: (() -> Void)?, onError: ((Error) -> Void)?) {
        showAdIfAvailable(viewController: viewController,
                          onOpen: onOpen,
                          onClose: onClose,
                          onError: onError
        )
    }
}
