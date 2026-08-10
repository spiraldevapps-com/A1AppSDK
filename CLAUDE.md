# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What This Is

A1AppSDK is a Swift Package Manager library (minimum iOS 15, macOS 12) that bundles common mobile app infrastructure — ads, analytics, consent management, app updates, and session recording — into a single SDK for internal use across A1Apps products.

## Build & Development Commands

This is a pure SPM package with no test targets. Build and resolve via Xcode or the command line:

```bash
# Resolve dependencies
swift package resolve

# Build the package
swift build

# Open in Xcode (preferred for development)
open Package.swift
```

There are no lint, test, or run scripts defined in this package.

## Architecture

All public surface lives under `Sources/A1AppSDK/Classes/`. There are two layers:

**Singleton managers** — each wraps a third-party SDK and exposes a simplified API:
- `AdsHandler.shared` — primary entry point for ad operations; wraps `Ads.shared` (Google Mobile Ads). Configure once via `configureAds(config:pro:)`. Controls all ad types through `AdsConfiguration` (decoded from Firebase Remote Config JSON).
- `EventManager.shared` — fan-out analytics logger; sends events simultaneously to Firebase Analytics, Facebook App Events, and AppMetrica. Configure via `configureEventManager(appMetricaKey:userId:firebase:facebook:)`.
- `ConsentManager.shared` — wraps Google UMP SDK for GDPR consent flow. Call `gatherConsent()` at app launch; call `showGDPR(from:adConfig:isPro:completionHandler:)` before initializing ads.
- `AppUpdate.shared` — drives force/optional update alerts using a `VersionConfig` struct (typically sourced from Firebase Remote Config). Configure via `configureAppUpdate(url:config:)` then call `checkUpdate()`.
- `ClarityManager` — thin wrapper to initialize Microsoft Clarity session recording.

**Ads module** (`Classes/Ads_Module/`):
- `Public Files/` — `AdsType` protocol, `AdsConfiguration` struct, `AdsHandler`, `AdsError`, `AdsBannerType`, `AdsType`
- `Internal Files/` — concrete `GADMobileAds` adapters for each format (banner, interstitial, rewarded, rewarded interstitial, native, app open). Each wraps a GAD type and exposes `load()` / `show()` / `stopLoading()`.
- The `Ads` singleton is the only class that directly imports and calls `GADMobileAds`.

**Supporting types:**
- `TrackingViewModel` — ATT (App Tracking Transparency) request and IDFA access.
- `Validator` — static email validation.
- `Utility` — alert presentation and App Store URL opening (used by `AppUpdate`).
- `Localization` — localized strings for update alert copy.
- `DebugViewController` / `DebugAdsViewController` — internal debug UI (loaded from `Debug.storyboard`).

## Key Design Patterns

**`AdsConfiguration`** is a `Codable` struct with snake_case remote keys (e.g., `inter_id`, `ads_enabled`). All fields have safe defaults via `init()` which uses AdMob test IDs. This is the data contract between Firebase Remote Config and the ads system.

**Ad interval logic** lives in `AdsHandler.canShowInterAd()` and `canShowAppOpenAd()`: ads are gated by `interInterval` (seconds between interstitials), `interClickInterval` (minimum taps before showing), and `appOpenInterInterval` (cooldown between app-open and interstitial ads).

**Pro/ads-disabled flow**: Pass `pro: true` to `AdsHandler.configureAds` to disable all ads globally. Calling `Ads.shared.setDisabled(true)` stops all loading and clears internal ad objects.

**Notification**: `Notification.Name.adsConfigureCompletion` is posted after `Ads.configure()` completes initialization, signaling that ads are ready to display.

## Dependencies (Package.swift)

| Package | Version | Purpose |
|---|---|---|
| Alamofire | 5.9.1 | Network reachability check in `AdsHandler` |
| firebase-ios-sdk | 12.6.0 | Analytics, Remote Config, Crashlytics, Auth, and more |
| facebook-ios-sdk | 18.0.2 | Facebook App Events analytics |
| appmetrica-sdk-ios | 5.14.0 | AppMetrica analytics |
| swift-package-manager-google-mobile-ads | 11.2.0 | AdMob ads |
| ShimmerSwift | 2.2.0 | Loading shimmer effect (used in native ad views) |
| clarity-apps | 3.4.4 | Microsoft Clarity session recording |
| intercom-ios-sp | 19.5.5 | Intercom customer messaging |
