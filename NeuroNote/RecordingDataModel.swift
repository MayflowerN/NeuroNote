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
    
    @Relationship(deleteRule: .cascade)
    var segments: [TranscriptionSegment] = []

    init(fileURL: URL, createdAt: Date = .now) {
        self.fileURL = fileURL
        self.createdAt = createdAt
    }
}
