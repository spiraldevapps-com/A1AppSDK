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
        .package(url: "https://github.com/Alamofire/Alamofire.git", exact: "5.9.1"),
        .package(url: "https://github.com/firebase/firebase-ios-sdk.git", exact: "11.15.0"),
        .package(url: "https://github.com/facebook/facebook-ios-sdk.git", exact: "18.0.0"),
        .package(url: "https://github.com/appmetrica/appmetrica-sdk-ios", exact: "5.8.1"),
        .package(url: "https://github.com/googleads/swift-package-manager-google-mobile-ads.git", exact: "11.2.0"),
        .package(url: "https://github.com/SwiftyJSON/SwiftyJSON.git", exact: "5.0.2"),
        .package(url: "https://github.com/BeauNouvelle/ShimmerSwift", exact: "2.2.0"),
        .package(url: "https://github.com/helpscout/beacon-ios-sdk", exact: "3.0.1"),
        .package(url: "https://github.com/microsoft/clarity-apps", exact: "3.0.10"),
        
    ],
    targets: [
        // Targets are the basic building blocks of a package, defining a module or a test suite.
        // Targets can depend on other targets in this package and products from dependencies.
        .target(
            name: "A1AppSDK",
            dependencies: [
// MARK: - Alamofire
                "Alamofire",
// MARK: - Firebase
                .product(name: "FirebaseAnalytics", package: "firebase-ios-sdk"),
                .product(name: "FirebaseAuth", package: "firebase-ios-sdk"),
                .product(name: "FirebaseAppCheck", package: "firebase-ios-sdk"),
                .product(name: "FirebaseAppDistribution-Beta", package: "firebase-ios-sdk"),
                .product(name: "FirebaseCrashlytics", package: "firebase-ios-sdk"),
                .product(name: "FirebaseDatabase", package: "firebase-ios-sdk"),
                .product(name: "FirebaseDynamicLinks", package: "firebase-ios-sdk"),
                .product(name: "FirebaseFirestore", package: "firebase-ios-sdk"),
                .product(name: "FirebaseFunctions", package: "firebase-ios-sdk"),
                .product(name: "FirebaseInAppMessaging-Beta", package: "firebase-ios-sdk"),
                .product(name: "FirebaseInstallations", package: "firebase-ios-sdk"),
                .product(name: "FirebaseMessaging", package: "firebase-ios-sdk"),
                .product(name: "FirebasePerformance", package: "firebase-ios-sdk"),
                .product(name: "FirebaseRemoteConfig", package: "firebase-ios-sdk"),
                .product(name: "FirebaseStorage", package: "firebase-ios-sdk"),
// MARK: - Facebook
                .product(name: "FacebookCore", package: "facebook-ios-sdk"),
                .product(name: "FacebookLogin", package: "facebook-ios-sdk"),
                .product(name: "FacebookAEM", package: "facebook-ios-sdk"),
                .product(name: "FacebookBasics", package: "facebook-ios-sdk"),
                // MARK: - Appmetrica.
                .product(name: "AppMetricaCore", package: "appmetrica-sdk-ios"),
                .product(name: "AppMetricaCrashes", package: "appmetrica-sdk-ios"),
                
                .product(name: "GoogleMobileAds", package: "swift-package-manager-google-mobile-ads"),
                
                .product(name: "SwiftyJSON", package: "SwiftyJSON"),
                
                .product(name: "ShimmerSwift", package: "ShimmerSwift"),
                
                .product(name: "Beacon-iOS", package: "beacon-ios-sdk"),
                
                .product(name: "Clarity", package: "clarity-apps"),

                
            ], path: "Sources"),
    ]
)
