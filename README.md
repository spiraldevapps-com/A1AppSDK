# A1AppSDK

A Swift package that owns the third-party frameworks the A1 apps share: Firebase, Meta, AppMetrica, Clarity, Adapty, AdMob and UMP consent, Intercom, StoreKit 2, Apple Search Ads attribution, App Tracking Transparency, reachability, the rating prompt and the update prompt. An app supplies its keys, registers the modules it wants, and calls `A1SDK.shared`. All vendor setup, ordering and re-identification happen inside the package.

Version 3.0, branch `a1sdk_v3.0`. iOS 15 and later. Swift tools 5.10.

## Documentation

- `docs/Integration-Guide.md`: setup, the configuration reference, every public method with its signature and a usage snippet, migration from 1.0.x and troubleshooting.
- `docs/Architecture.md`: how the SDK is structured, what each of the nineteen modules does, and the mechanisms they share.

## Quick start

```swift
import A1AppSDK

// AppDelegate, application(_:didFinishLaunchingWithOptions:)
A1SDK.shared.register(A1SDK.standardModules())

A1SDK.shared.configure(with: A1Configuration(
    appMetricaAPIKey: "<YOUR_APPMETRICA_KEY>",
    clarityProjectID: "<YOUR_CLARITY_PROJECT_ID>",
    subscriptionAPIKey: "<YOUR_ADAPTY_KEY>",
    prefetchedPlacements: [A1Placement("<YOUR_PLACEMENT_ID>")],
    support: .init(apiKey: "<YOUR_INTERCOM_API_KEY>", appID: "<YOUR_INTERCOM_APP_ID>"),
    initialEntitlement: MyAppDefaults.isPro,
    appStoreURL: "https://apps.apple.com/app/id<YOUR_APP_STORE_ID>"
))

A1SDK.shared.application(application, didFinishLaunchingWithOptions: launchOptions)
```

Forward the remaining UIKit callbacks: `didRegisterForRemoteNotifications(deviceToken:)` from the AppDelegate, and `applicationDidBecomeActive(_:)` and `application(_:open:options:)` from the SceneDelegate in a scene-based app. The Integration Guide shows the complete wiring.

Two rules every integrator needs:

- Every `observe` call returns an `A1ObservationToken` that cancels the subscription when it is released. Store it in a property.
- On a first launch the user id is empty until anonymous sign-in resolves. The SDK re-identifies every vendor itself when the id arrives; app code observes `A1SDK.shared.identity` rather than reading it once.

