//
//  TranscriptionSegmentModel.swift
//  NeuroNote
//
//  Created by Ellie on 7/3/25.
//

import Foundation
import SwiftData

/// Represents a 30-second audio segment and its transcription status.
@Model
class TranscriptionSegment {
    /// URL to the individual audio segment file.
    var audioURL: URL
    
    /// Optional text result from transcription.
    var transcriptionText: String?
    
    /// Timestamp of when this segment was created.
    var createdAt: Date
    
    /// Current status of the transcription (pending, transcribing, completed, failed).
    var status: TranscriptionStatus
    
    /// How many times transcription has been attempted (for retry logic).
    var attemptCount: Int
    
    /// Whether to use Whisper (vs Apple STT) for this segment.
    var useWhisper: Bool
    
    /// Back-reference to the parent recording.
    var parent: Recording?

    init(
        audioURL: URL,
        transcriptionText: String? = nil,
        createdAt: Date = .now,
        status: TranscriptionStatus = .pending,
        attemptCount: Int = 0,
        useWhisper: Bool = true,
        parent: Recording? = nil
    ) {
        self.audioURL = audioURL
        self.transcriptionText = transcriptionText
        self.createdAt = createdAt
        self.status = status
        self.attemptCount = attemptCount
        self.useWhisper = useWhisper
        self.parent = parent
    }
}

/// Enum representing possible transcription states for a segment.
enum TranscriptionStatus: String, Codable, CaseIterable {
    case pending
    case transcribing
    case completed
    case failed
}
