//
//  ClarityManager.swift
//  A1IOSLib
//
//  Created by Tushar Goyal on 10/07/24.
//

import Foundation
import Clarity

public struct ClarityManager {
    
    public static func initialized(id: String) {
        let clarityConfig = ClarityConfig(projectId: id, logLevel: .verbose)
        ClaritySDK.initialize(config: clarityConfig)
    }
    static func setCustomUser(id: String) {
        ClaritySDK.setCustomUserId(id)
    }
}
