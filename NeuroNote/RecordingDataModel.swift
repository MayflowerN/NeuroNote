//
//  RecordingDataModel.swift
//  NeuroNote
//
//  Created by Ellie on 7/2/25.
//

import Foundation
import SwiftData

@Model
class Recording {
    var fileURL: URL
    var createdAt: Date
    
    init(fileURL: URL, createdAt: Date) {
        self.fileURL = fileURL
        self.createdAt = createdAt
    }
}
