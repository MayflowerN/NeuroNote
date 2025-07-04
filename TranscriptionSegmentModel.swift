//
//  TranscriptionSegmentModel.swift
//  NeuroNote
//
//  Created by Ellie on 7/3/25.
//

import Foundation
import SwiftData

@Model
class TranscriptionSegment {
    var audioURL: URL
    var transcriptionText: String?
    var createdAt: Date
    var status: TranscriptionStatus
    var attemptCount: Int
    var parent: Recording?

    init(audioURL: URL, transcriptionText: String? = nil, createdAt: Date = .now, status: TranscriptionStatus = .pending, attemptCount: Int = 0, parent: Recording? = nil) {
        self.audioURL = audioURL
        self.transcriptionText = transcriptionText
        self.createdAt = createdAt
        self.status = status
        self.attemptCount = attemptCount
        self.parent = parent
    }
}

enum TranscriptionStatus: String, Codable, CaseIterable {
    case pending
    case transcribing
    case completed
    case failed
}
