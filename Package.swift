// swift-tools-version: 5.10
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "A1AppSDK",
    platforms: [
           .iOS(.v14), // Adjust platform version as needed
           .macOS(.v12),
       ],
    products: [
        // Products define the executables and libraries a package produces, making them visible to other packages.
        .library(
            name: "A1AppSDK",
            targets: ["A1AppSDK"]),
    ],
    dependencies: [
        .package(url: "https://github.com/firebase/firebase-ios-sdk.git", exact: "11.9.0"),
        .package(url: "https://github.com/yandexmobile/metrica-sdk-ios", exact: "4.5.2"),
        .package(url: "https://github.com/googleads/swift-package-manager-google-mobile-ads.git", exact: "11.2.0"),
        .package(url: "https://github.com/BeauNouvelle/ShimmerSwift", exact: "2.2.0"),
        .package(url: "https://github.com/microsoft/clarity-apps", exact: "2.1.2"),
        
    ],
    targets: [
        // Targets are the basic building blocks of a package, defining a module or a test suite.
        // Targets can depend on other targets in this package and products from dependencies.
        .target(
            name: "A1AppSDK",
            dependencies: [
// MARK: - Firebase
                .product(name: "FirebaseAnalytics", package: "firebase-ios-sdk"),
                .product(name: "FirebaseAuth", package: "firebase-ios-sdk"),
                .product(name: "FirebaseAppDistribution-Beta", package: "firebase-ios-sdk"),
                .product(name: "FirebaseCrashlytics", package: "firebase-ios-sdk"),
                .product(name: "FirebaseDynamicLinks", package: "firebase-ios-sdk"),
                .product(name: "FirebaseInAppMessaging-Beta", package: "firebase-ios-sdk"),
                .product(name: "FirebaseMessaging", package: "firebase-ios-sdk"),
                .product(name: "FirebasePerformance", package: "firebase-ios-sdk"),
                .product(name: "FirebaseRemoteConfig", package: "firebase-ios-sdk"),

                .product(name: "YandexMobileMetrica", package: "metrica-sdk-ios"),
                
                .product(name: "GoogleMobileAds", package: "swift-package-manager-google-mobile-ads"),
                                
                .product(name: "ShimmerSwift", package: "ShimmerSwift"),
                                
                .product(name: "Clarity", package: "clarity-apps"),

                
            ], path: "Sources"),
    ]
)
