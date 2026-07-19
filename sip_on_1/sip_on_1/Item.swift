//
//  Item.swift
//  sip_on_1
//
//  Created by BIN on 2026/7/7.
//

import Foundation
import SwiftData

@Model
final class Item {
    var timestamp: Date
    
    init(timestamp: Date) {
        self.timestamp = timestamp
    }
}
