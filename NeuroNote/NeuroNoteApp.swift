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
        let speechRecognizer = SpeechRecognizer()
        let recorder = Recorder(speechRecognizer: speechRecognizer)

        WindowGroup {
            RecordingView(Recorder: recorder)
        }
        .modelContainer(for: [Recording.self, TranscriptionSegment.self])
    }
}
