//
//  HSBeacon.swift
//  A1IOSLib
//
//  Created by Tushar Goyal on 12/09/23.
//
//
//import Foundation
//import Beacon
//
//public struct HSBeaconManager {
//    
//    public static func open(id: String, firebaseId: String, userJoinDate: String, isPro: Bool) {
//        let user = HSBeaconUser()
//        user.addAttribute(withKey: "firebase-id", value: firebaseId)
//        user.addAttribute(withKey: "is-pro", value: isPro.description)
//        user.addAttribute(withKey: "member-since", value: userJoinDate)
//        HSBeacon.identify(user)
//        let settings = HSBeaconSettings(beaconId: id)
//        HSBeacon.open(settings)
//    }
//    
//}
