//
//  DebugTextCell.swift
//  A1IOSLib_Example
//
//  Created by Navnidhi Sharma on 27/12/23.
//  Copyright © 2023 CocoaPods. All rights reserved.
//

import UIKit

class DebugTextCell: UITableViewCell {
    @IBOutlet weak var debugTextLabel: UILabel!
    
    override func awakeFromNib() {
        super.awakeFromNib()
        // Initialization code
    }

    override func setSelected(_ selected: Bool, animated: Bool) {
        super.setSelected(selected, animated: animated)

        // Configure the view for the selected state
    }
    
}
