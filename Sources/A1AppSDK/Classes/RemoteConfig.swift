//
//  FirebaseHandler.swift
//  A1Apps
//
//  Created by Navnidhi on 01/01/24.
//  Copyright © 2024 A1Apps. All rights reserved.
//
import Foundation

// MARK: - AdConfig
public struct AdsConfiguration: Codable {
    public let interInterval: Int
    public let adsEnabled, interEnabled: Bool
    public let interID: String
    public let appOpenEnabled: Bool
    public let appOpenID: String
    public let bannerEnabled: Bool
    public let bannerID: String
    public let appOpenInterval, appOpenInterInterval: Int
    public let interClickInterval: Int
    public var rewardedEnabled: Bool
    public var rewardedID: String
    public var rewardedInterstitialID: String = ""
    public var nativeID: String = ""

    enum CodingKeys: String, CodingKey {
        case interInterval = "inter_interval"
        case adsEnabled = "ads_enabled"
        case interEnabled = "inter_enabled"
        case interID = "inter_id"
        case appOpenEnabled = "app_open_enabled"
        case appOpenID = "app_open_id"
        case bannerEnabled = "banner_enabled"
        case bannerID = "banner_id"
        case appOpenInterval = "app_open_interval"
        case appOpenInterInterval = "app_open_inter_interval"
        case interClickInterval = "inter_click_interval"
        case rewardedEnabled = "rewarded_enabled"
        case rewardedID = "rewarded_id"
    }
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        
        self.interInterval = try container.decodeIfPresent(Int.self, forKey: .interInterval) ?? 0
        self.adsEnabled = try container.decodeIfPresent(Bool.self, forKey: .adsEnabled) ?? false
        self.interEnabled = try container.decodeIfPresent(Bool.self, forKey: .interEnabled) ?? false
        self.interID = try container.decodeIfPresent(String.self, forKey: .interID) ?? ""
        self.appOpenEnabled = try container.decodeIfPresent(Bool.self, forKey: .appOpenEnabled) ?? false
        self.appOpenID = try container.decodeIfPresent(String.self, forKey: .appOpenID) ?? ""
        self.bannerEnabled = try container.decodeIfPresent(Bool.self, forKey: .bannerEnabled) ?? false
        self.bannerID = try container.decodeIfPresent(String.self, forKey: .bannerID) ?? ""
        self.appOpenInterval = try container.decodeIfPresent(Int.self, forKey: .appOpenInterval) ?? 0
        self.appOpenInterInterval = try container.decodeIfPresent(Int.self, forKey: .appOpenInterInterval) ?? 0
        self.interClickInterval = try container.decodeIfPresent(Int.self, forKey: .interClickInterval) ?? 0
        
        // Provide default values for potentially missing fields
        self.rewardedEnabled = try container.decodeIfPresent(Bool.self, forKey: .rewardedEnabled) ?? false
        self.rewardedID = try container.decodeIfPresent(String.self, forKey: .rewardedID) ?? ""
        self.rewardedInterstitialID = ""
        self.nativeID = ""
    }
    
    public init() {
        interInterval = 10
        adsEnabled = true
        interEnabled = true
        interID = "ca-app-pub-3940256099942544/4411468910"
        appOpenEnabled = true
        appOpenID = "ca-app-pub-3940256099942544/9257395921"
        bannerEnabled = true
        bannerID = "ca-app-pub-3940256099942544/2934735716"
        appOpenInterval = 10
        appOpenInterInterval = 10
        interClickInterval = 2
        rewardedEnabled = true
        rewardedID = "ca-app-pub-3940256099942544/1712485313"
        rewardedInterstitialID = "ca-app-pub-3940256099942544/6978759866"
        nativeID = "ca-app-pub-3940256099942544/3986624511"
    }
    
    public init(interInterval: Int, adsEnabled: Bool, interEnabled: Bool, interID: String, appOpenEnabled: Bool , appOpenID: String, bannerEnabled: Bool, bannerID: String, appOpenInterval: Int, appOpenInterInterval: Int, interClickInterval: Int, rewardedEnabled: Bool, rewardedID: String) {
        self.interInterval = interInterval
        self.adsEnabled = adsEnabled
        self.interEnabled = interEnabled
        self.interID = interID
        self.appOpenEnabled = appOpenEnabled
        self.appOpenID = appOpenID
        self.bannerEnabled = bannerEnabled
        self.bannerID = bannerID
        self.appOpenInterval = appOpenInterval
        self.appOpenInterInterval = appOpenInterInterval
        self.interClickInterval = interClickInterval
        self.rewardedEnabled = rewardedEnabled
        self.rewardedID = rewardedID
    }
}

// MARK: - VersionConfig
public struct VersionConfig: Codable {
    public let minVersion, stableVersion: String

    enum CodingKeys: String, CodingKey {
        case minVersion, stableVersion
    }
    
    public init() {
        self.minVersion = ""
        self.stableVersion = ""
    }
    
    public init(minVersion: String, stableVersion: String) {
        self.minVersion = minVersion
        self.stableVersion = stableVersion
    }
}
