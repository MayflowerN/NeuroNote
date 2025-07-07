//
//  RecordingDataModel.swift
//  NeuroNote
//
//  Created by Ellie on 7/2/25.
//

import Foundation
import SwiftData

/// Represents a full recording session (e.g. a complete user session).
@Model
class Recording: Identifiable {
    @Attribute(.unique) var id: UUID
    var fileURL: URL
    var createdAt: Date

    @Relationship(deleteRule: .cascade)
    var segments: [TranscriptionSegment] = []

    init(id: UUID = UUID(), fileURL: URL, createdAt: Date = .now) {
        self.id = id
        self.fileURL = fileURL
        self.createdAt = createdAt
    }
}
