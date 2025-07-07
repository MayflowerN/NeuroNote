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
    // Stores the latest recognized transcription text for live display or debugging
    var recognizedText: String = "No speech recognized"
    
    init() {
        requestAuthorization()
    }
    
    /// Requests user permission for speech recognition via Apple's Speech framework.
    /// Must be done before attempting any STT (speech-to-text) tasks.
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

    /// Orchestrates transcription of a saved audio file for a specific segment.
    /// The logic checks which STT service (Whisper or Apple) to use.
    func transcribeAudioFile(at url: URL, for segment: TranscriptionSegment, in context: ModelContext) {
        print("🎙️ Starting transcription for: \(url.lastPathComponent)")
        Task {
            do {
                // NOTE: Toggle between Apple STT and Whisper based on this boolean.
                // Currently hardcoded to Apple STT (false branch).
                if false {
                    try await transcribeWithWhisper(url: url, segment: segment, context: context)
                } else {
                    try await transcribeWithApple(url: url, segment: segment, context: context)
                }
            } catch {
                // If transcription fails, handle retry/fallback behavior
                await handleTranscriptionFailure(url: url, segment: segment, context: context)
            }
        }
    }
    
    /// Transcribes audio using OpenAI Whisper via backend HTTP request.
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

    /// Transcribes audio using Apple's on-device STT engine (SFSpeechRecognizer).
    private func transcribeWithApple(url: URL, segment: TranscriptionSegment, context: ModelContext) async throws {
        try await withCheckedThrowingContinuation { continuation in

            // When running tests (e.g., in CI), skip real transcription for stability.
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

            // Set up Apple STT recognizer and request
            let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
            let request = SFSpeechURLRecognitionRequest(url: url)
            request.shouldReportPartialResults = false  // we only want final output

            var didFinish = false  // Ensures continuation is only called once

            // Start recognition task
            let task = recognizer?.recognitionTask(with: request) { result, error in
                guard !didFinish else { return }

                if let result = result, result.isFinal {
                    // Transcription successful
                    segment.transcriptionText = result.bestTranscription.formattedString
                    segment.status = .completed
                    try? context.save()
                    print("Apple STT transcribed: \(segment.transcriptionText ?? "")")
                    continuation.resume()
                    didFinish = true
                } else if let error = error {
                    // Transcription failed
                    continuation.resume(throwing: error)
                    didFinish = true
                }
            }

            // Safety timeout in case task hangs (e.g. due to silence or system issue)
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

    /// Handles retry logic for failed transcriptions using exponential backoff.
    /// Falls back to Apple STT if Whisper fails too many times.
    private func handleTranscriptionFailure(url: URL, segment: TranscriptionSegment, context: ModelContext) async {
        segment.attemptCount += 1
        print("Transcription failed. Retrying \(segment.attemptCount)...")
        
        if segment.attemptCount >= 5 {
            if segment.useWhisper {
                // If Whisper failed 5 times, fallback to Apple STT for this segment
                print("Switching to Apple STT fallback")
                segment.useWhisper = false
            } else {
                // If both Whisper and STT fail repeatedly, mark segment as failed
                segment.status = .failed
                print("Max transcription retries reached")
            }
        } else {
            // Wait exponentially longer before retrying (e.g. 2, 4, 8 seconds...)
            let delay = pow(2.0, Double(segment.attemptCount))
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            transcribeAudioFile(at: url, for: segment, in: context)
        }

        try? context.save()
    }
}
