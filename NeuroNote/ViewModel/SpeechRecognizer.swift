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
    // Stores the latest recognized transcription text
    var recognizedText: String = "No speech recognized"
    
    init() {
        requestAuthorization()
    }
    
    /// Requests user permission for speech recognition
    private func requestAuthorization() {
        SFSpeechRecognizer.requestAuthorization { authStatus in
            DispatchQueue.main.async {
                switch authStatus {
                case .authorized:
                    print("Speech recognition authorized")
                case .denied, .restricted, .notDetermined:
                    print("Speech recognition not authorized")
                @unknown default:
                    fatalError("Unknown speech auth status")
                }
            }
        }
    }

    /// Starts transcription for a given audio file and segment
    func transcribeAudioFile(at url: URL, for segment: TranscriptionSegment, in context: ModelContext) {
        print("🎙️ Starting transcription for: \(url.lastPathComponent)")
        Task {
            do {
                // Toggle between Apple STT and Whisper here if needed
                if false {
                    try await transcribeWithWhisper(url: url, segment: segment, context: context)
                } else {
                    try await transcribeWithApple(url: url, segment: segment, context: context)
                }
            } catch {
                await handleTranscriptionFailure(url: url, segment: segment, context: context)
            }
        }
    }
    
    /// Transcribes audio using OpenAI Whisper API
    private func transcribeWithWhisper(url: URL, segment: TranscriptionSegment, context: ModelContext) async throws {
        segment.status = .transcribing
        try? context.save()
        print("📡 Sending audio to Whisper API...")

        let text = try await WhisperService.transcribe(audioURL: url)
        segment.transcriptionText = text
        segment.status = .completed
        try? context.save()
        print("Whisper transcribed: \(text)")
    }

    /// Transcribes audio using Apple's built-in speech recognition
    private func transcribeWithApple(url: URL, segment: TranscriptionSegment, context: ModelContext) async throws {
        try await withCheckedThrowingContinuation { continuation in
            // Skip live STT logic during unit tests to avoid unnecessary network/system calls
            #if DEBUG
            if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil {
                print("🧪 Skipping live STT during test")
                segment.transcriptionText = "Mocked transcription"
                segment.status = .completed
                try? context.save()
                continuation.resume()
                return
            }
            #endif

            let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
            let request = SFSpeechURLRecognitionRequest(url: url)
            request.shouldReportPartialResults = false

            var didFinish = false

            let task = recognizer?.recognitionTask(with: request) { result, error in
                guard !didFinish else { return }

                if let result = result, result.isFinal {
                    // Success: Save result and complete
                    segment.transcriptionText = result.bestTranscription.formattedString
                    segment.status = .completed
                    try? context.save()
                    print("Apple STT transcribed: \(segment.transcriptionText ?? "")")
                    continuation.resume()
                    didFinish = true
                } else if let error = error {
                    // Failure: Report error
                    continuation.resume(throwing: error)
                    didFinish = true
                }
            }

            // Timeout fallback in case Apple STT does not complete
            DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
                if !didFinish {
                    print("Forcing task cancel due to no final result")
                    task?.cancel()
                    continuation.resume(throwing: NSError(domain: "STTTimeout", code: -1))
                    didFinish = true
                }
            }
        }
    }

    /// Handles transcription failures and applies retry logic with exponential backoff
    private func handleTranscriptionFailure(url: URL, segment: TranscriptionSegment, context: ModelContext) async {
        segment.attemptCount += 1
        print("Transcription failed. Retrying \(segment.attemptCount)...")
        
        if segment.attemptCount >= 5 {
            if segment.useWhisper {
                // Fallback to Apple STT if Whisper failed too many times
                print("Switching to Apple STT fallback")
                segment.useWhisper = false
            } else {
                // Mark as failed if both systems fail too many times
                segment.status = .failed
                print("Max transcription retries reached")
            }
        } else {
            // Retry after exponential delay
            let delay = pow(2.0, Double(segment.attemptCount))
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            transcribeAudioFile(at: url, for: segment, in: context)
        }

        try? context.save()
    }
}
