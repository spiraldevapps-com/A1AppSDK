//
//  DebugTableViewCell.swift
//  A1IOSLib_Example
//
//  Created by Navnidhi Sharma on 27/12/23.
//  Copyright © 2023 CocoaPods. All rights reserved.
//

import UIKit

class DebugTableViewCell: UITableViewCell {
    @IBOutlet weak var titleLabel: UILabel!
    var show:()->() = {}
    var load:()->() = {}
    var type: DebugAdsType = .inter
    override func awakeFromNib() {
        super.awakeFromNib()
        // Initialization code
    }
    
    @IBAction func showAction(_ sender: Any) {
        show()
    }
    @IBAction func loadAction(_ sender: Any) {
        load()
    }
}
