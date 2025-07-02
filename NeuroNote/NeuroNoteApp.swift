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
        WindowGroup {
            RecordingView(Recorder: Recorder())
        }
        .modelContainer(for: Recording.self)
    }
}
