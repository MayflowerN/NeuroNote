//
//  SpeechRecognizer.swift
//  NeuroNote
//
//  Created by Ellie on 7/3/25.
//

import Foundation
import Speech

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

    func transcribeAudioFile(at url: URL) {
        let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
        let request = SFSpeechURLRecognitionRequest(url: url)

        recognizer?.recognitionTask(with: request) { result, error in
            if let result = result {
                self.recognizedText = result.bestTranscription.formattedString
                print("📝 Transcribed: \(self.recognizedText)")
            } else if let error = error {
                print("⚠️ Transcription failed: \(error.localizedDescription)")
            }
        }
    }
}
