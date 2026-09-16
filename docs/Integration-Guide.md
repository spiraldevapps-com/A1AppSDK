# A1AppSDK 3.0 Integration Guide

Setup, then every public method with its signature and a usage snippet. For how the SDK works inside, see `Architecture.md`.

All keys are placeholders. Types prefixed `My` are yours, not the SDK's.

## Contents

1. Install
2. Wire up
3. `A1Configuration`
4. `A1SDK` facade
5. Analytics
6. Subscriptions and paywalls
7. Ads
8. Consent
9. Support
10. Identity
11. Remote Config
12. App update
13. Rating
14. Tracking
15. Attribution
16. Reachability
17. Performance
18. Push token
19. Vendor accessors
20. Moving from 1.0.x
21. Rules
22. Troubleshooting

## 1. Install

Add the package in Xcode: File, Add Package Dependencies, URL `https://github.com/spiraldevapps-com/A1AppSDK.git`, exact version. Add the `A1AppSDK` product to your app target. Confirm it appears under target, General, Frameworks Libraries and Embedded Content, or nothing will compile.

Declare any package your own code imports. A module that reaches you only because the SDK links it will break the day the SDK drops it.

Keep in the app target:

| Item | Required by |
|---|---|
| `GoogleService-Info.plist` | every Firebase module |
| `GADApplicationIdentifier` in Info.plist | ads |
| `NSUserTrackingUsageDescription` | the tracking prompt |
| Facebook app id, client token, URL scheme | Meta events |
| Push Notifications capability | FCM and Intercom push |
| `SKAdNetworkItems` | ad attribution |

Delete any `FirebaseApp.configure()` call of your own. The SDK makes it.

## 2. Wire up

```swift
import A1AppSDK

extension A1Placement {
    static let onboarding = A1Placement("<YOUR_PLACEMENT_ID>")
    static let settings   = A1Placement("<YOUR_OTHER_PLACEMENT_ID>")
    static let all: [A1Placement] = [.onboarding, .settings]
}

enum SDKBootstrap {

    // Retain these. An A1ObservationToken cancels its subscription when released.
    private static var entitlementToken: A1ObservationToken?
    private static var identityToken: A1ObservationToken?

    static func boot() {
        A1SDK.shared.register(A1SDK.standardModules())

        A1SDK.shared.configure(with: A1Configuration(
            appMetricaAPIKey: "<YOUR_APPMETRICA_KEY>",
            clarityProjectID: "<YOUR_CLARITY_PROJECT_ID>",
            subscriptionAPIKey: "<YOUR_ADAPTY_KEY>",
            prefetchedPlacements: A1Placement.all,
            support: .init(apiKey: "<YOUR_INTERCOM_API_KEY>",
                           appID: "<YOUR_INTERCOM_APP_ID>"),
            initialEntitlement: AppSettings.isPro,
            appStoreURL: "https://apps.apple.com/app/id<YOUR_APP_STORE_ID>"
        ))

        entitlementToken = A1SDK.shared.subscriptions?.observeEntitlement { isPro in
            AppSettings.isPro = isPro
        }
        identityToken = A1SDK.shared.identity.observe { userID in
            guard !userID.isEmpty else { return }
            AppSettings.userID = userID
        }
    }
}
```

AppDelegate:

```swift
func application(_ application: UIApplication,
                 didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
    SDKBootstrap.boot()
    A1SDK.shared.application(application, didFinishLaunchingWithOptions: launchOptions)
    return true
}

func application(_ application: UIApplication,
                 didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
    A1SDK.shared.didRegisterForRemoteNotifications(deviceToken: deviceToken)
}
```

SceneDelegate, if your Info.plist declares `UIApplicationSceneManifest`. UIKit never calls the AppDelegate equivalents in that case:

```swift
func sceneDidBecomeActive(_ scene: UIScene) {
    A1SDK.shared.applicationDidBecomeActive(UIApplication.shared)
}

func scene(_ scene: UIScene, openURLContexts URLContexts: Set<UIOpenURLContext>) {
    guard let url = URLContexts.first?.url else { return }
    A1SDK.shared.application(UIApplication.shared, open: url, options: [:])
}
```

Without a scene manifest, forward `applicationDidBecomeActive(_:)` and `application(_:open:options:)` from the AppDelegate instead.

## 3. `A1Configuration`

One initialiser, every parameter defaulted. Listed in initialiser order.

| Parameter | Type | Default | Controls |
|---|---|---|---|
| `appMetricaAPIKey` | `String?` | `nil` | AppMetrica. Empty means never activated |
| `isFirebaseAnalyticsEnabled` | `Bool` | `true` | Firebase Analytics sink |
| `isMetaAnalyticsEnabled` | `Bool` | `true` | Meta sink and SDK initialisation |
| `clarityProjectID` | `String?` | `nil` | Clarity session recording |
| `subscriptionAPIKey` | `String?` | `nil` | Adapty. Empty disables paywalls and entitlement |
| `premiumAccessLevel` | `String` | `"premium"` | Access level that counts as pro |
| `prefetchedPlacements` | `[A1Placement]` | `[]` | Paywalls warmed at launch |
| `paywallLocale` | `String?` | `nil` | Locale for paywall content |
| `support` | `SupportCredentials?` | `nil` | Intercom credentials |
| `isSearchAdsAttributionEnabled` | `Bool` | `false` | Apple Search Ads attribution |
| `isTrackingEnabled` | `Bool` | `true` | Whether the ATT prompt may be shown |
| `isPerformanceMonitoringEnabled` | `Bool?` | `nil` | Firebase Performance. `nil` keeps the Info.plist setting |
| `isNetworkStatusLoggingEnabled` | `Bool` | `false` | Log an event on connectivity change |
| `entitlementProductIDs` | `[String]` | `[]` | StoreKit ids that count as entitlement |
| `initialEntitlement` | `Bool?` | `nil` | Pro flag to seed on first launch after adoption |
| `versionConfigKey` | `String` | `"version_config"` | Remote Config key holding `VersionConfig` |
| `appStoreURL` | `String?` | `nil` | Opened by the update prompt |
| `eventNameOverrides` | `[String: String]` | `[:]` | Rename SDK events, `[sdkName: yourName]` |
| `eventParameterProvider` | `(() -> [String: Any])?` | `nil` | Parameters merged into every SDK event |
| `paywallLoadTimeout` | `TimeInterval` | `10` | Seconds before a paywall presentation gives up |
| `isLoggingEnabled` | `Bool` | `false` | Boot logs and vendor verbose logging |
| `custom` | `[String: Any]` | `[:]` | Free-form values for modules |

`SupportCredentials`:

```swift
public init(apiKey: String, appID: String, isInAppMessagingEnabled: Bool = true)
```

`custom` keys the standard modules read, all rating thresholds:

```swift
custom: [
    "ratingMinimumSessions": 5,
    "ratingMinimumSignificantEvents": 3,
    "ratingMinimumInterval": 60 * 60 * 24 * 30,
    "ratingQuietPeriod": 120
]
```

## 4. `A1SDK` facade

#### `register`

```swift
public func register(_ module: A1Module)
public func register(_ modules: [A1Module])
```

Adds modules. Call before `configure(with:)`. A second module with the same identifier is ignored, so registering your own first lets it win over a standard one. Registering after boot configures that module immediately.

```swift
A1SDK.shared.register(A1SDK.standardModules())

// Replace a standard module with your own configured instance.
A1SDK.shared.register(RemoteConfigAdapter(minimumFetchInterval: 0))
A1SDK.shared.register(A1SDK.standardModules())

// Leave a module out entirely; it is never constructed.
A1SDK.shared.register(A1SDK.standardModules(excluding: [AppUpdateAdapter.self]))
```

#### `configure(with:)`

```swift
public func configure(with configuration: A1Configuration)
```

Boots every registered module in phase order, synchronously, on the main thread. Runs once; a second call is ignored. Called off the main thread it hops and blocks.

```swift
A1SDK.shared.configure(with: A1Configuration(subscriptionAPIKey: "<YOUR_ADAPTY_KEY>"))
```

#### `module(_:)`

```swift
public func module<T>(_ type: T.Type = T.self) -> T?
```

Reaches any module by type, for APIs the four provider protocols do not cover. Returns `nil` when that module is not registered. Safe before boot.

```swift
let rating = A1SDK.shared.module(RatingAdapter.self)
let performance = A1SDK.shared.module(PerformanceAdapter.self)
```

#### Provider properties

```swift
public var analytics: AnalyticsDispatcher     // never nil
public var subscriptions: SubscriptionProvider?
public var ads: AdsProvider?
public var support: SupportProvider?
public let identity: A1Identity               // never nil
public var configuration: A1Configuration
public var isConfigured: Bool
public var registeredModules: [(identifier: String, phase: Int)]
```

Each resolves to the first registered conformer. All are safe before boot.

```swift
if A1SDK.shared.isConfigured {
    print(A1SDK.shared.registeredModules)   // [(identifier, phase)] in boot order
}
```

#### Lifecycle forwarding

```swift
public func application(_ application: UIApplication,
                        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?)
public func applicationDidBecomeActive(_ application: UIApplication)
@discardableResult
public func application(_ application: UIApplication,
                        open url: URL,
                        options: [UIApplication.OpenURLOptionsKey: Any] = [:]) -> Bool
public func didRegisterForRemoteNotifications(deviceToken: Data)
```

Each is relayed to the modules that observe lifecycle, in phase order. The URL variant returns `true` if any module handled it, and every module sees the URL regardless. See section 2 for placement.

## 5. Analytics

Accessor `A1SDK.shared.analytics`, an `AnalyticsDispatcher`. One call reaches every attached sink.

#### `log(_:)`

```swift
public func log(_ event: A1Event)
```

Sends one event. `A1Event` takes a name plus optional parameters, and is `ExpressibleByStringLiteral`.

```swift
A1SDK.shared.analytics.log("event_app_export_clicked")

A1SDK.shared.analytics.log(A1Event("event_app_export_clicked",
                                   parameters: ["format": "pdf", "pages": 12]))

// Parallel arrays, for call sites that already build them that way.
A1SDK.shared.analytics.log(A1Event("event_app_export_clicked",
                                   keys: ["format"], values: ["pdf"]))
```

#### `reportError(_:message:parameters:)`

```swift
public func reportError(_ rawName: String, message: String, parameters: [String: Any]?)
```

Reports a non-fatal. It reaches Crashlytics as an `NSError` whose domain is the name, and AppMetrica as an error report. Include `FirebaseAnalyticsAdapter.errorCodeParameter` as an `Int` to set the `NSError` code, which is how Crashlytics groups.

```swift
A1SDK.shared.analytics.reportError("API Error",
                                   message: error.localizedDescription,
                                   parameters: [FirebaseAnalyticsAdapter.errorCodeParameter: statusCode,
                                                "url": url.absoluteString])
```

#### `setUserProperty(_:for:)`

```swift
public func setUserProperty(_ value: String?, for name: String)
```

Sets a user-scoped property on every sink that supports one. Pass `nil` to clear.

```swift
A1SDK.shared.analytics.setUserProperty("granted", for: "att_status")
```

#### `identify(userID:)`

```swift
public func identify(userID: String)
```

Associates later events with a user id on every sink. The SDK calls this for you whenever identity resolves, so you rarely need it.

```swift
A1SDK.shared.analytics.identify(userID: "<USER_ID>")
```

#### `attach(_:)` and `attachedProviderNames`

```swift
public func attach(_ sink: AnalyticsProvider)
public var attachedProviderNames: [String]
```

Adds your own sink. Anything buffered during boot, and the current user id, are replayed into it. The names list is for a debug screen.

```swift
final class MySink: AnalyticsProvider {
    var providerName: String { "MySink" }
    func log(_ event: A1Event) { /* forward to your backend */ }
}

A1SDK.shared.analytics.attach(MySink())
print(A1SDK.shared.analytics.attachedProviderNames)   // ["Firebase", "AppMetrica", "Meta", "MySink"]
```

`AnalyticsProvider` requires only `log(_:)`. `providerName`, `setUserProperty`, `identify` and `reportError` have defaults.

Two typed helpers exist for the SDK's own vocabulary, usable from app code:

```swift
A1SDK.shared.analytics.log(.event_app_first_open)                       // A1EventKey
A1SDK.shared.analytics.reportError(.firebase_authentication_error,
                                   message: "…", parameters: nil)
```

## 6. Subscriptions and paywalls

Accessor `A1SDK.shared.subscriptions`, a `SubscriptionProvider`.

#### `isPro`

```swift
var isPro: Bool { get }
```

Cached entitlement flag. Never calls the vendor, so it is safe during layout. Persisted across launches and seeded from `A1Configuration.initialEntitlement` on the first launch after adoption.

```swift
let isPro = A1SDK.shared.subscriptions?.isPro ?? false
upgradeBanner.isHidden = isPro
```

#### `observeEntitlement(_:)`

```swift
@discardableResult
func observeEntitlement(_ handler: @escaping (Bool) -> Void) -> A1ObservationToken
```

Fires immediately with the current value, then on every change: purchase, restore, the launch profile check, or a lapse. Handlers run on the main queue. Retain the token.

```swift
private var entitlementToken: A1ObservationToken?

entitlementToken = A1SDK.shared.subscriptions?.observeEntitlement { [weak self] isPro in
    self?.isPro = isPro
}
```

#### `refreshEntitlement(completion:)`

```swift
func refreshEntitlement(completion: ((Bool) -> Void)?)
```

Re-checks with the vendor and publishes the result to observers. Call it after a purchase you made outside the SDK. The completion runs on the vendor's queue.

```swift
A1SDK.shared.subscriptions?.refreshEntitlement { isPro in
    DispatchQueue.main.async { self.render(isPro: isPro) }
}
```

#### `present(_:from:callbacks:)`

```swift
func present(_ placement: A1Placement,
             from viewController: UIViewController,
             callbacks: A1PaywallCallbacks)
```

Resolves and presents a paywall. The common path.

```swift
A1SDK.shared.subscriptions?.present(.settings, from: self, callbacks: A1PaywallCallbacks(
    onLoading:  { [weak self] isLoading in self?.setLoader(isLoading) },
    onError:    { [weak self] error in self?.showAlert(error.localizedDescription) },
    onPurchase: { [weak self] result in
        if case .success = result { self?.unlock() }
    },
    onRestore:  { [weak self] result in
        switch result {
        case .success:                   self?.unlock()
        case .failed(.nothingToRestore): self?.showAlert("Nothing to restore")
        default:                         break
        }
    },
    onClose:    { },
    onDismiss:  { [weak self] in self?.resumeInterruptedFlow() }
))
```

`A1PaywallCallbacks` is a struct of optional closures:

| Closure | Fires when |
|---|---|
| `onLoading((Bool) -> Void)` | `true` at once, `false` when ready, failed or timed out |
| `onError((A1PurchaseError) -> Void)` | load or render failed, the presenter left the hierarchy, or a JSON placement arrived with no `onRemoteConfig` |
| `onPurchase((A1PurchaseResult) -> Void)` | a purchase ended: `.success`, `.cancelled`, `.pending`, `.failed` |
| `onRestore((A1PurchaseResult) -> Void)` | a restore started inside the paywall ended |
| `onClose(() -> Void)` | the user closed it without buying |
| `onDismiss(() -> Void)` | the paywall finished dismissing. Exactly once per presentation |
| `onRemoteConfig((A1PaywallPayload) -> Void)` | the placement has no vendor-designed screen, only JSON |

Presenting a placement whose paywall is already on screen is ignored.

#### `paywall(for:completion:)`

```swift
func paywall(for placement: A1Placement,
             completion: @escaping (Result<A1PaywallConfig, A1PurchaseError>) -> Void)
```

Resolves without presenting, for an app that presents the controller itself. Note that callbacks are only attached by `present`, so a controller you present this way reports nothing back.

```swift
A1SDK.shared.subscriptions?.paywall(for: .onboarding) { result in
    switch result {
    case .success(.builder(let controller)):
        self.navigationController?.pushViewController(controller, animated: true)
    case .success(.remoteConfig(let payload)):
        self.showNativePaywall(payload)
    case .failure(let error):
        print(error.localizedDescription)
    }
}
```

#### `prefetch(_:)`

```swift
func prefetch(_ placements: [A1Placement])
```

Warms the cache so presentation is instant. `A1Configuration.prefetchedPlacements` does this at launch; call it directly for placements decided later.

```swift
A1SDK.shared.subscriptions?.prefetch([.onboarding, .settings])
```

#### `logPaywallShown(_:)`

```swift
func logPaywallShown(_ placement: A1Placement)
```

Records an impression for a paywall your app drew from a `.remoteConfig` payload. Vendor-designed paywalls record their own, and this call refuses them, so it can never double count.

```swift
callbacks.onRemoteConfig = { payload in
    let model: MyPaywallModel? = payload.decode()
    let screen = MyPaywallViewController(model: model, placement: payload.placement)
    self.present(screen, animated: true) {
        A1SDK.shared.subscriptions?.logPaywallShown(payload.placement)
    }
}
```

#### `restore(completion:)`

```swift
func restore(completion: @escaping (A1PurchaseResult) -> Void)
```

Restores purchases outside a paywall, for a settings row. The completion runs on the vendor's queue.

```swift
A1SDK.shared.subscriptions?.restore { result in
    DispatchQueue.main.async {
        switch result {
        case .success:                   self.showAlert("Purchases restored")
        case .failed(.nothingToRestore): self.showAlert("Nothing to restore")
        case .failed(let error):         self.showAlert(error.localizedDescription)
        default:                         break
        }
    }
}
```

#### `setIntegrationIdentifier(key:value:)`

```swift
func setIntegrationIdentifier(key: String, value: String)
```

Attaches a third-party id for revenue attribution. The SDK already links the Firebase, AppMetrica and Meta ids; use this only for a vendor it does not know about.

```swift
A1SDK.shared.subscriptions?.setIntegrationIdentifier(key: "branch_id", value: branchID)
```

#### `isEntitlementResolved`

```swift
public var isEntitlementResolved: Bool
```

On `AdaptyAdapter`, not the protocol. `true` once the vendor has answered this launch. Until then `isPro` is the value cached from the previous session.

```swift
let settled = A1SDK.shared.module(AdaptyAdapter.self)?.isEntitlementResolved ?? false
```

#### Payload decoding

```swift
public var dictionary: [String: Any]? { get }
public func decode<T: Decodable>(_ type: T.Type = T.self) -> T?
```

On `A1PaywallPayload`, which carries `placement`, `locale` and `jsonString`. Decoding returns `nil` rather than throwing, so a malformed payload cannot break a paywall.

```swift
let model: MyPaywallModel? = payload.decode()
let raw = payload.dictionary?["headline"] as? String
```

`NativePaywallParser` offers the SDK's own shape, `A1NativePaywall`, with `title`, `subtitle`, `features`, `products`, `ctaTitle`, `footerText`, `variant` and `showsCloseButton`:

```swift
let paywall = NativePaywallParser.parse(payload)              // A1NativePaywall?
let mine: MyModel? = NativePaywallParser.parse(payload, as: MyModel.self)
```

Products keep dashboard order, including entries with an empty `identifier`, so check before offering one for purchase.

#### Result types

```swift
public enum A1PurchaseResult { case success(A1Transaction), cancelled, pending, failed(A1PurchaseError) }
public struct A1Transaction { public let productIdentifier: String; public let placement: A1Placement?; public let isActive: Bool }
public enum A1PurchaseError: Error {
    case notConnected, paywallUnavailable, productsUnavailable
    case purchaseFailed(String), restoreFailed(String), nothingToRestore
    case renderingFailed(String), unknown(String)
}
```

## 7. Ads

Accessor `A1SDK.shared.ads`, an `AdsProvider`.

#### `configure(_:isPro:)`

```swift
func configure(_ configuration: AdsConfiguration, isPro: Bool)
```

Hands over your ad settings. Nothing loads until consent is resolved. Entitlement changes switch ads off on their own, so the `isPro` you pass is only the starting value.

```swift
let config = remote.decode(AdsConfiguration.self, forKey: "<YOUR_ADS_CONFIG_KEY>") ?? AdsConfiguration()
A1SDK.shared.ads?.configure(config, isPro: A1SDK.shared.subscriptions?.isPro ?? false)
```

`AdsConfiguration` decodes from Remote Config with these keys, all optional:

| JSON key | Property |
|---|---|
| `ads_enabled` | `adsEnabled` |
| `inter_enabled`, `inter_id`, `inter_interval`, `inter_click_interval` | interstitial |
| `app_open_enabled`, `app_open_id`, `app_open_interval`, `app_open_inter_interval` | app open |
| `banner_enabled`, `banner_id` | banner |
| `rewarded_enabled`, `rewarded_id` | rewarded |
| `native_enabled`, `native_id` | native |

#### `canShow(_:)` and `suppressionReason(for:)`

```swift
func canShow(_ format: A1AdFormat) -> Bool
func suppressionReason(for format: A1AdFormat) -> A1AdSuppressionReason?
```

Whether a format may be shown now, and why not. Both advance the frequency counters, so call once per opportunity. Calling twice to double check changes how often ads appear.

```swift
if A1SDK.shared.ads?.canShow(.interstitial) == true {
    // show it
}

switch A1SDK.shared.ads?.suppressionReason(for: .appOpen) {
case nil:               break   // may show
case .adsDisabled:      break   // no config yet, or ads_enabled false
case .userIsPro:        break
case .formatDisabled:   break
case .notConnected:     break
case .notLoaded:        break
case .anotherAdShowing: break
case .withinInterval:   break   // frequency cap
}
```

#### `show(_:from:callbacks:)`

```swift
func show(_ format: A1AdFormat,
          from viewController: UIViewController,
          callbacks: A1AdCallbacks)
```

Presents a full-screen format: `.appOpen`, `.interstitial`, `.rewarded`, `.rewardedInterstitial`.

```swift
func showInterstitialThen(_ next: @escaping () -> Void) {
    guard let ads = A1SDK.shared.ads, ads.canShow(.interstitial) else { next(); return }
    ads.show(.interstitial, from: self, callbacks: A1AdCallbacks(
        onClose:    { next() },
        onError:    { _ in next() },
        onNotReady: { next() }
    ))
}
```

`A1AdCallbacks`: `onOpen`, `onClose`, `onError(Error)`, `onReward(NSDecimalNumber)`, `onNotReady`. Route your continuation through exactly one of `onClose`, `onError` and `onNotReady`, since a missing ad fires the latter two.

```swift
A1SDK.shared.ads?.show(.rewarded, from: self, callbacks: A1AdCallbacks(
    onClose:  { self.finish() },
    onError:  { _ in self.finish() },
    onReward: { amount in self.grant(amount) }
))
```

#### `makeBanner(in:callbacks:)`

```swift
func makeBanner(in viewController: UIViewController,
                callbacks: A1AdCallbacks) -> A1BannerAd?
```

Builds a banner, or `nil` when banners are unavailable. Retain the returned object; add its `containerView` to your layout and call `show()`. `A1BannerAd` also has `remove()` and `updateLayout()`.

```swift
private var banner: A1BannerAd?

func attachBanner() {
    guard let ads = A1SDK.shared.ads, ads.canShow(.banner),
          let banner = ads.makeBanner(in: self, callbacks: A1AdCallbacks())
    else { return }
    self.banner = banner
    bannerSlot.addSubview(banner.containerView)
    banner.show()
}

override func viewWillTransition(to size: CGSize, with coordinator: UIViewControllerTransitionCoordinator) {
    super.viewWillTransition(to: size, with: coordinator)
    coordinator.animate { _ in self.banner?.updateLayout() }
}
```

#### `state(for:)`

```swift
func state(for format: A1AdFormat) -> A1AdState
```

Whether that format is loaded, showing or loading. A cached read.

```swift
let state = A1SDK.shared.ads?.state(for: .interstitial) ?? .idle(.interstitial)
if state.isReady { /* … */ }
```

#### `setDisabled(_:)`

```swift
func setDisabled(_ isDisabled: Bool)
```

Turns all ads off or back on. Disabling stops loading and releases loaded ads.

```swift
A1SDK.shared.ads?.setDisabled(true)
```

#### `prepareRewarded()`

```swift
public func prepareRewarded()
```

On `AdMobAdapter`. Rewarded ads load separately from the main set; call this once your configuration is applied.

```swift
A1SDK.shared.module(AdMobAdapter.self)?.prepareRewarded()
```

## 8. Consent

Accessor `A1SDK.shared.module(ConsentAdapter.self)`. Ads do not start until consent resolves.

#### `presentConsentForm(from:completion:)`

```swift
public func presentConsentForm(from viewController: UIViewController,
                               completion: @escaping () -> Void)
```

Presents the consent form when one is required. The completion runs exactly once on every path, including when nothing is shown, so it is safe to navigate from it. Ads reconfigure themselves afterwards.

```swift
A1SDK.shared.module(ConsentAdapter.self)?.presentConsentForm(from: self) {
    self.moveToHome()
}
```

#### `isResolved` and `isPrivacyOptionsRequired`

```swift
public var isResolved: Bool
public var isPrivacyOptionsRequired: Bool
```

Whether the consent round trip has finished, and whether a user who already consented must be offered a privacy options entry point. Both are safe before boot.

```swift
settingsPrivacyRow.isHidden =
    !(A1SDK.shared.module(ConsentAdapter.self)?.isPrivacyOptionsRequired ?? false)
```

#### `whenResolved(_:)` and `observeResolution(_:)`

```swift
public func whenResolved(_ work: @escaping () -> Void)
@discardableResult
public func observeResolution(_ handler: @escaping () -> Void) -> A1ObservationToken
```

The first runs once, at the first resolution or immediately if already resolved. The second runs at every resolution, including the one after the form is answered, and returns a token to retain.

```swift
A1SDK.shared.module(ConsentAdapter.self)?.whenResolved {
    self.startSomethingThatNeedsConsent()
}

private var consentToken: A1ObservationToken?
consentToken = A1SDK.shared.module(ConsentAdapter.self)?.observeResolution {
    self.refreshAdSlots()
}
```

## 9. Support

Accessor `A1SDK.shared.support`, a `SupportProvider`. The SDK logs the user in and keeps the pro attribute current on its own.

#### `present(from:)`

```swift
func present(from viewController: UIViewController)
```

Opens the support messenger.

```swift
A1SDK.shared.support?.present(from: self)
```

#### `updateUser(attributes:)`

```swift
func updateUser(attributes: [String: Any])
```

Merges your own attributes into the ones the SDK sends. Before identity resolves they are held and sent with the login that follows.

```swift
A1SDK.shared.support?.updateUser(attributes: [
    "last_purchased_plan": plan,
    "documents_created": count
])
```

#### `unreadCount`

```swift
var unreadCount: Int { get }
```

Unread conversations, for a badge. `0` before the module is configured.

```swift
badge.text = "\(A1SDK.shared.support?.unreadCount ?? 0)"
```

#### `registerForPush(deviceToken:)`

```swift
func registerForPush(deviceToken: Data)
```

Alternative to the lifecycle forward. Either path works and the same token is never registered twice.

```swift
A1SDK.shared.support?.registerForPush(deviceToken: deviceToken)
```

## 10. Identity

Accessor `A1SDK.shared.identity`, an `A1Identity`.

#### `userID` and `isResolved`

```swift
public var userID: String { get }
public var isResolved: Bool { get }
```

The current id, empty until sign-in resolves, which is a valid state on a first launch.

```swift
let userID = A1SDK.shared.identity.userID
```

#### `observe(_:)`

```swift
@discardableResult
public func observe(_ handler: @escaping (String) -> Void) -> A1ObservationToken
```

Fires immediately with the current value, including the empty one, then on every change. Main queue. Retain the token.

```swift
private var identityToken: A1ObservationToken?

identityToken = A1SDK.shared.identity.observe { userID in
    guard !userID.isEmpty else { return }
    AppSettings.userID = userID
}
```

#### `update(userID:)`

```swift
public func update(userID newValue: String)
```

Publishes an id from your own sign-in. Every vendor re-identifies itself. Observers run only when the value actually changes.

```swift
A1SDK.shared.identity.update(userID: signedInUser.uid)
```

#### `A1ObservationToken.cancel()`

```swift
public func cancel()
```

Ends a subscription early. `deinit` calls it, which is why a token you do not store unsubscribes at once.

```swift
identityToken?.cancel()
identityToken = nil
```

## 11. Remote Config

Accessor `A1SDK.shared.module(RemoteConfigAdapter.self)`. The SDK fetches and decodes; the schema is yours.

#### `refresh(completion:)`

```swift
public func refresh(completion: ((Result<Bool, Error>) -> Void)? = nil)
```

Fetches and activates. The `Bool` says whether new values arrived this fetch. Decoding works against cached values too, so decode either way.

```swift
let remote = A1SDK.shared.module(RemoteConfigAdapter.self)

remote?.refresh { result in
    if case .failure(let error) = result { print(error) }
    if let config: MyConfig = remote?.decode(forKey: "<YOUR_KEY>") {
        apply(config)
    }
}
```

#### `decode(_:forKey:)` and the typed getters

```swift
public func decode<T: Decodable>(_ type: T.Type = T.self, forKey key: String) -> T?
public func string(forKey key: String) -> String?
public func bool(forKey key: String) -> Bool
public func int(forKey key: String) -> Int
public func double(forKey key: String) -> Double
```

`decode` returns `nil` on a missing key or a shape mismatch. The scalars return `nil`, `false` and `0` before the module has booted.

```swift
let ads: AdsConfiguration? = remote?.decode(forKey: "<YOUR_ADS_KEY>")
let showBanner = remote?.bool(forKey: "show_banner") ?? false
let maxPages = remote?.int(forKey: "max_pages") ?? 0
```

#### `setDefaults(_:)` and `minimumFetchInterval`

```swift
public func setDefaults(_ defaults: [String: NSObject])
public var minimumFetchInterval: TimeInterval   // init parameter, default 3600
```

Defaults set before boot are applied when the module configures. The fetch interval is read once at boot, so pass it to the initialiser rather than assigning later.

```swift
A1SDK.shared.register(RemoteConfigAdapter(minimumFetchInterval: isDebugBuild ? 0 : 3600))
A1SDK.shared.module(RemoteConfigAdapter.self)?.setDefaults(["show_banner": true as NSObject])
```

## 12. App update

Accessor `A1SDK.shared.module(AppUpdateAdapter.self)`. Exclude the module if your app has no update prompts.

#### `apply(_:appStoreURL:)`

```swift
public func apply(_ config: VersionConfig, appStoreURL: String? = nil)
```

Supplies a freshly fetched payload. Passing `nil` for the URL keeps `A1Configuration.appStoreURL`. `VersionConfig` has `minVersion` and `stableVersion`, both compared numerically against `CFBundleShortVersionString`.

```swift
if let version: VersionConfig = remote?.decode(forKey: A1SDK.shared.configuration.versionConfigKey) {
    A1SDK.shared.module(AppUpdateAdapter.self)?.apply(version)
}
```

#### `checkForUpdate(canShowOptional:)`

```swift
public func checkForUpdate(canShowOptional: Bool = true)
```

Shows whichever prompt is due. A non-empty `minVersion` above the running version forces; a higher `stableVersion` offers. Hops to the main thread itself and does nothing until a payload exists. The force prompt returns on every foreground until the user updates.

```swift
A1SDK.shared.module(AppUpdateAdapter.self)?.checkForUpdate()
```

#### `isPromptShowing`

```swift
public var isPromptShowing: Bool
```

Whether an update alert is on screen. It becomes true on the run loop turn after `checkForUpdate`, not the same turn.

```swift
guard A1SDK.shared.module(AppUpdateAdapter.self)?.isPromptShowing != true else { return }
```

Alert copy comes from these keys, each with an English default you override in your own `Localizable.strings`: `FORCE_TITLE`, `FORCE_MESSAGE`, `OPTIONAL_TITLE`, `OPTIONAL_MESSAGE`, `UPDATE_NOW`, `MAYBE_LATER`.

## 13. Rating

Accessor `A1SDK.shared.module(RatingAdapter.self)`.

#### `policy`

```swift
public var policy: Policy
public init(policy: Policy = Policy())
```

Thresholds a prompt must clear: `minimumSessions` (3), `minimumSignificantEvents` (2), `minimumInterval` (60 days), `quietPeriod` (300s). Set it before boot through the initialiser, or after boot on the module. `A1Configuration.custom` keys layer on top of whatever it holds.

```swift
var policy = RatingAdapter.Policy()
policy.minimumSessions = 0
policy.quietPeriod = 300
A1SDK.shared.register(RatingAdapter(policy: policy))
```

#### `noteSignificantEvent()` and `noteInterruption()`

```swift
public func noteSignificantEvent()
public func noteInterruption()
```

The first records a positive moment worth being asked about. The second opens the quiet period after a paywall or full-screen ad, so a prompt does not read as part of the dismissal.

```swift
A1SDK.shared.module(RatingAdapter.self)?.noteSignificantEvent()   // export finished
A1SDK.shared.module(RatingAdapter.self)?.noteInterruption()       // paywall dismissed
```

#### `requestReviewIfAppropriate(reason:)` and `requestReview(reason:)`

```swift
public func requestReviewIfAppropriate(reason: String)
public func requestReview(reason: String)
```

The first enforces the policy, for prompts the app initiates. The second skips it, for a prompt the user asked for, such as tapping stars. Both need a foreground scene and log `a1sdk_rating_prompt_requested`.

```swift
A1SDK.shared.module(RatingAdapter.self)?.requestReviewIfAppropriate(reason: "export_completed")
A1SDK.shared.module(RatingAdapter.self)?.requestReview(reason: "rating_screen")
```

#### `canRequestReview`

```swift
public var canRequestReview: Bool
```

Whether every threshold is met right now, for an app that wants to decide itself.

```swift
if A1SDK.shared.module(RatingAdapter.self)?.canRequestReview == true { showOwnRatingSheet() }
```

## 14. Tracking

Accessor `A1SDK.shared.module(TrackingAdapter.self)`. Boot reads the status and never prompts.

#### `requestAuthorization(completion:)`

```swift
public func requestAuthorization(completion: @escaping (A1TrackingStatus) -> Void)
```

Shows the ATT prompt at a moment you choose. A request made while the app is not yet active is held and shown when it becomes active. With `isTrackingEnabled: false` it completes with the current status and shows nothing.

```swift
A1SDK.shared.module(TrackingAdapter.self)?.requestAuthorization { status in
    A1SDK.shared.analytics.setUserProperty(status == .authorized ? "granted" : "denied",
                                           for: "att_status")
}
```

#### `status`, `isAuthorized`, `advertisingIdentifier`

```swift
public var status: A1TrackingStatus       // .notDetermined, .authorized, .denied, .restricted
public var isAuthorized: Bool
public var advertisingIdentifier: UUID?   // nil unless authorised
```

Reading the status never prompts.

```swift
let tracking = A1SDK.shared.module(TrackingAdapter.self)
if tracking?.status == .notDetermined { /* ask later */ }
let idfa = tracking?.advertisingIdentifier?.uuidString
```

#### `observe(_:)`

```swift
@discardableResult
public func observe(_ handler: @escaping (A1TrackingStatus) -> Void) -> A1ObservationToken
```

Fires immediately with the current status, then on change. Main queue. Retain the token.

```swift
private var trackingToken: A1ObservationToken?
trackingToken = A1SDK.shared.module(TrackingAdapter.self)?.observe { status in
    self.updateAdPersonalisation(status == .authorized)
}
```

## 15. Attribution

Accessor `A1SDK.shared.module(AttributionAdapter.self)`. Off unless `isSearchAdsAttributionEnabled` is `true`.

#### `whenResolved(_:)`, `payload`, `attributionToken`

```swift
public func whenResolved(_ handler: @escaping ([String: Any]?) -> Void)
public var payload: [String: Any]?
public var attributionToken: String?
```

The handler runs once, on the main queue, when attribution has settled. The payload is `nil` only when the fetch failed and nothing was cached.

```swift
A1SDK.shared.module(AttributionAdapter.self)?.whenResolved { payload in
    guard let campaign = payload?["campaignId"] else { return }
    print("attributed to \(campaign)")
}
```

## 16. Reachability

Accessor `A1SDK.shared.module(ReachabilityAdapter.self)`. One monitor for the process.

#### `isConnected`, `isExpensive`, `isConstrained`

```swift
public var isConnected: Bool
public var isExpensive: Bool     // cellular or hotspot
public var isConstrained: Bool   // Low Data Mode
```

Cached reads, not probes. `isConnected` starts `true` until the first path update, so a launch-time request is not suppressed by a false negative.

```swift
guard A1SDK.shared.module(ReachabilityAdapter.self)?.isConnected != false else {
    showOfflineMessage(); return
}
```

#### `observe(_:)`

```swift
@discardableResult
public func observe(_ handler: @escaping (Bool) -> Void) -> A1ObservationToken
```

Fires immediately, then only when connectivity flips. A change of interface on a live connection does not fire.

```swift
private var reachabilityToken: A1ObservationToken?
reachabilityToken = A1SDK.shared.module(ReachabilityAdapter.self)?.observe { isConnected in
    self.banner.isHidden = isConnected
}
```

## 17. Performance

Accessor `A1SDK.shared.module(PerformanceAdapter.self)`. Every handle is optional and `nil` when collection is off, so call sites never test configuration.

#### `startTrace(_:)` and `stop(_:)`

```swift
public func startTrace(_ name: String) -> A1TraceHandle?
public func stop(_ handle: A1TraceHandle)
```

Starts and ends a trace by handle. A handle is a value; stopping it twice does nothing.

```swift
let performance = A1SDK.shared.module(PerformanceAdapter.self)
let trace = performance?.startTrace("export_pdf")
trace?.setValue("share_sheet", forAttribute: "source")
trace?.increment("pages", by: Int64(pageCount))
if let trace { performance?.stop(trace) }
```

`A1TraceHandle` offers `increment(_:by:)`, `setValue(_:forCounter:)` and `setValue(_:forAttribute:)`.

#### `measure(_:_:)`

```swift
@discardableResult
public func measure<T>(_ name: String, _ work: () throws -> T) rethrows -> T
```

Times a block and returns its result. Reported whether the block returns or throws.

```swift
let document = try performance?.measure("open_document") { try loader.open(url) }
```

#### `beginStage(_:)` and `endStage(_:)`

```swift
@discardableResult
public func beginStage(_ name: String) -> A1TraceHandle?
public func endStage(_ name: String)
```

For a span that starts and ends in different files, such as a launch stage. Held by name. Re-entering a stage abandons the previous one rather than reporting a span across both.

```swift
// splash
A1SDK.shared.module(PerformanceAdapter.self)?.beginStage("splash_to_home")
// home
A1SDK.shared.module(PerformanceAdapter.self)?.endStage("splash_to_home")
```

## 18. Push token

Accessor `A1SDK.shared.module(MessagingAdapter.self)`. Only the token hand-off lives here. Asking for permission and presenting notifications stay in the app.

#### `onTokenRefresh`

```swift
public var onTokenRefresh: ((String) -> Void)?
```

Called when a token is issued or rotated. A token that arrived before you assigned the handler is delivered once on assignment, so wiring it late loses nothing.

```swift
A1SDK.shared.module(MessagingAdapter.self)?.onTokenRefresh = { token in
    AppSettings.fcmToken = token
    MyBackend.register(token)
}
```

#### `currentToken(completion:)`

```swift
public func currentToken(completion: @escaping (String?) -> Void)
```

Asks for the current token. Completes with `nil` rather than crashing when called before boot.

```swift
A1SDK.shared.module(MessagingAdapter.self)?.currentToken { token in
    print(token ?? "no token yet")
}
```

## 19. Vendor accessors

Small, specific reads on individual modules.

```swift
// Did Firebase come up?
let firebaseReady = A1SDK.shared.module(FirebaseCoreAdapter.self)?.isConfigured ?? false

// Clarity session recording
let clarity = A1SDK.shared.module(ClarityAdapter.self)
let sessionURL = clarity?.currentSessionURL
clarity?.setCurrentScreen("Editor")
clarity?.sendCustomEvent("export_started")     // returns Bool
clarity?.setTag("plan", "annual")              // returns Bool

// StoreKit, Apple's own view of entitlement, separate from the subscription vendor
let storeKit = A1SDK.shared.module(StoreKitAdapter.self)
let entitled = storeKit?.hasActiveEntitlement ?? false
let country = storeKit?.storefrontCountryCode
storeKit?.refresh { entitled in print(entitled) }

// Vendor ids, if you report them somewhere of your own
let appInstanceID = A1SDK.shared.module(FirebaseAnalyticsAdapter.self)?.appInstanceID
let deviceID = A1SDK.shared.module(AppMetricaAdapter.self)?.deviceID
A1SDK.shared.module(MetaAdapter.self)?.whenInitialized { anonymousID in
    print(anonymousID)
}

// Record a StoreKit 2 transaction as revenue in Firebase
A1SDK.shared.module(FirebaseAnalyticsAdapter.self)?.logTransaction(transaction)
```

## 20. Moving from 1.0.x

1. Point the package at 3.x and add the `A1AppSDK` product to the target.
2. Declare any package your code imports that the old SDK used to bring in for you.
3. Delete every vendor bootstrap the SDK now owns: `FirebaseApp.configure()`, the Meta launch call, `Adapty.activate`, `AdaptyUI.activate`, Clarity init, `AppMetrica.activate`, `Intercom.setApiKey`, the Messaging delegate, and the consent request. Replace them with the two calls in section 2.
4. Forward the four lifecycle callbacks, including the two from the scene delegate.
5. Keep existing call sites compiling by turning each old manager into a thin forwarder onto the matching provider. No screen needs to change.
6. Mirror SDK state into the flags your app already reads, with the tokens retained.
7. Pass your existing pro flag as `initialEntitlement`, or a paying user reads as free until the vendor answers.
8. Exclude modules your app has no use for.
9. Review the rating policy. The defaults are stricter than most apps ran before.

Then verify: a cold first launch resolves the user id and seeds entitlement; a purchase flips entitlement, stops ads and fires `onDismiss` once; ads stay silent before consent and start after the form; the same event reaches every vendor; the push token arrives without an Intercom error.

Two overloads from 1.0.x still compile but are deprecated, and their ad arguments are ignored because ads reconfigure themselves after consent:

```swift
ConsentManager.showGDPR(from:adConfig:isPro:completionHandler:)     // use showGDPR(from:completionHandler:)
ConsentAdapter.presentConsentForm(from:adConfiguration:isPro:completion:)   // use presentConsentForm(from:completion:)
```

## 21. Rules

**Retain every observation token.** `observe`, `observeEntitlement` and `observeResolution` return an `A1ObservationToken` that cancels on release. The methods are `@discardableResult`, so nothing warns you. A dropped token means the handler fires once and never again.

**The user id is empty on a first launch.** Sign-in is a network call and launch does not wait. Observe the id rather than reading it once. The SDK re-identifies every vendor when it arrives.

**Scene-based apps must forward from the scene delegate.** The AppDelegate foreground and URL methods are never called, so Meta activation, the deferred tracking prompt and the update re-check go silent.

**Ads wait for consent.** Where the consent form is required, an app that never presents it gets no ads that session.

**`canShow` and `suppressionReason` change ad pacing.** Call one of them once per opportunity.

**`reportError` reaches Crashlytics.** Every call becomes a non-fatal as well as an AppMetrica error report.

**Event names belong to the app.** The SDK dispatches raw names. Rename its own events with `eventNameOverrides` rather than editing an adapter, which would change every other app at once.

## 22. Troubleshooting

| Symptom | Cause | Fix |
|---|---|---|
| Crash at launch naming Firebase | Something touched Firebase before the SDK booted, or a custom module resolves a vendor in `init` | Resolve vendors in `configure(context:)`. Move app Firebase calls after boot |
| An observer fires once, never again | The token was not retained | Store it in a property |
| Events missing from one vendor | That vendor's key or flag is missing, or a rename applies | Check `attachedProviderNames` and `eventNameOverrides` |
| Meta events never arrive | `didFinishLaunching` was not forwarded | Forward it right after `configure(with:)` |
| Paywall does not appear | No subscription key, load timed out, the presenter left the hierarchy, or a JSON placement with no `onRemoteConfig` | Read `onError`, present from a screen that stays, add the handler |
| Ads never load | Consent unresolved, no configuration applied, ads disabled, or the user is pro | Read `suppressionReason(for:)` |
| Update alert shows raw keys | The six string keys are not defined in that language | Define them in `Localizable.strings` |
| Rating prompt never appears | Policy thresholds, no foreground scene, or Apple's own yearly cap | Tune `policy`, or use `requestReview(reason:)` for user-initiated taps |
