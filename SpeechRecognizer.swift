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
        let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
        let request = SFSpeechURLRecognitionRequest(url: url)

        segment.status = .transcribing
        try? context.save()

        recognizer?.recognitionTask(with: request) { result, error in
            DispatchQueue.main.async {
                if let result = result {
                    segment.transcriptionText = result.bestTranscription.formattedString
                    segment.status = .completed
                    print("📝 Transcribed: \(segment.transcriptionText ?? "")")
                } else if let error = error {
                    segment.status = .failed
                    print("⚠️ Transcription failed: \(error.localizedDescription)")
                }

                try? context.save()
            }
        }
    }
}
