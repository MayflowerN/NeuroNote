//
//  NeuroNoteApp.swift
//  NeuroNote
//
//  Created by Ellie on 7/1/25.
//

import SwiftUI
import SwiftData

@main
struct NeuroNoteApp: App {
    var body: some Scene {
        // Initialize shared speech recognizer and recorder
        let speechRecognizer = SpeechRecognizer()
        let recorder = Recorder(speechRecognizer: speechRecognizer)

        WindowGroup {
            // Inject the recorder into the main view
            RecordingView(recorder: recorder)
        }
        // Provide SwiftData model container for persistence
        .modelContainer(for: [Recording.self, TranscriptionSegment.self])
    }
}
