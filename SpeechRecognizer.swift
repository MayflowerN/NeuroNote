//
//  SpeechRecognizer.swift
//  NeuroNote
//
//  Created by Ellie on 7/3/25.
//

import Foundation
import Speech
import SwiftData
@Observable
class SpeechRecognizer {
    var recognizedText: String = "No speech recognized"
    
    init() {
        requestAuthorization()
    }
    
    private func requestAuthorization() {
        SFSpeechRecognizer.requestAuthorization { authStatus in
            DispatchQueue.main.async {
                switch authStatus {
                case .authorized:
                    print("✅ Speech recognition authorized")
                case .denied, .restricted, .notDetermined:
                    print("❌ Speech recognition not authorized")
                @unknown default:
                    fatalError("Unknown speech auth status")
                }
            }
        }
    }
    func transcribeAudioFile(at url: URL, for segment: TranscriptionSegment, in context: ModelContext) {
        let maxAttempts = 5
        let delay = pow(2.0, Double(segment.attemptCount)) // 1st retry: 2s, 2nd: 4s, etc.
        
        guard segment.attemptCount < maxAttempts else {
            segment.status = .failed
            print("❌ Max transcription retries reached for segment at: \(url.lastPathComponent)")
            try? context.save()
            return
        }
        
        // Schedule retry with exponential delay
        DispatchQueue.global().asyncAfter(deadline: .now() + delay) {
            self._transcribe(url: url, segment: segment, context: context)
        }
    }
    private func _transcribe(url: URL, segment: TranscriptionSegment, context: ModelContext) {
        let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
        let request = SFSpeechURLRecognitionRequest(url: url)
        
        DispatchQueue.main.async {
            segment.status = .transcribing
            try? context.save()
        }
        
        recognizer?.recognitionTask(with: request) { result, error in
            DispatchQueue.main.async {
                if let result = result {
                    segment.transcriptionText = result.bestTranscription.formattedString
                    segment.status = .completed
                    print("📝 Transcribed: \(segment.transcriptionText ?? "")")
                } else {
                    segment.attemptCount += 1
                    segment.status = .pending
                    print("⚠️ Transcription failed. Retrying attempt \(segment.attemptCount)...")
                    
                    // Trigger another retry
                    self.transcribeAudioFile(at: url, for: segment, in: context)
                }
                
                try? context.save()
            }
        }
    }
}

