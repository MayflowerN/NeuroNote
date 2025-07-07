//
//  RecordingView.swift
//  NeuroNote
//
//  Created by Ellie on 7/2/25.
//
import SwiftUI
import SwiftData

/// Main UI for controlling and displaying recording functionality
struct RecordingView: View {
    @State var recorder: Recorder
    @Query(sort: [SortDescriptor(\Recording.createdAt, order: .reverse)], animation: .default)
    var recordings: [Recording]
    @Environment(\.modelContext) var modelContext

    var body: some View {
        NavigationStack {
            VStack {
                // If permission status has been determined
                if let permission = recorder.microphonePermissionGranted {
                    if permission {
                        // Show list of recordings and mic level meter
                        RecordingList(recordings: recordings)
                            .accessibilityLabel("Recording list")
                            .accessibilityHint("Displays all saved recordings")
                            .padding(.vertical)
                        // Start button
                        if recorder.recording == false {
                            Button(action: {
                                if recorder.isReady {
                                    do {
                                        try recorder.startRecording()
                                        UIAccessibility.post(notification: .announcement, argument: "Recording started")
                                    } catch {
                                        print("Failed to start recording: \(error.localizedDescription)")
                                    }
                                }
                            }) {
                                Image(systemName: "circle.fill")
                                    .resizable()
                                    .frame(width: 100, height: 100)
                                    .foregroundColor(.red)
                                    .padding(.bottom, 40)
                            }
                            .accessibilityLabel("Start Recording")
                            .accessibilityHint("Begins a new audio recording")
                        } else {
                            // Stop button
                            Button(action: {
                                recorder.stopRecording()
                                UIAccessibility.post(notification: .announcement, argument: "Recording stopped")
                                print("All saved recordings:")
                                recordings.forEach { print($0.fileURL.absoluteString) }
                            }) {
                                Image(systemName: "stop.fill")
                                    .resizable()
                                    .frame(width: 100, height: 100)
                                    .foregroundColor(.red)
                                    .padding(.bottom, 40)
                            }
                            .accessibilityLabel("Stop Recording")
                            .accessibilityHint("Stops the current recording")
                        }
                    } else {
                        // UI shown if microphone permission is denied
                        VStack(spacing: 16) {
                            Image(systemName: "mic.slash")
                                .resizable()
                                .frame(width: 60, height: 80)
                                .foregroundColor(.gray)
                                .accessibilityHidden(true)

                            Text("Microphone access is required to record.")
                                .multilineTextAlignment(.center)
                                .padding(.horizontal)
                                .accessibilityLabel("Microphone access required")
                                .accessibilityHint("Please enable microphone access in settings")

                            Button("Open Settings") {
                                if let url = URL(string: UIApplication.openSettingsURLString),
                                   UIApplication.shared.canOpenURL(url) {
                                    UIApplication.shared.open(url)
                                }
                            }
                            .padding()
                            .background(Color.red.opacity(0.8))
                            .foregroundColor(.white)
                            .cornerRadius(8)
                            .accessibilityLabel("Open Settings")
                            .accessibilityHint("Opens the Settings app to allow microphone access")
                        }
                        .padding()
                    }
                } else {
                    // UI shown while waiting for microphone permission to be determined
                    ProgressView("Checking microphone access...")
                        .padding()
                        .accessibilityLabel("Checking microphone access")
                        .accessibilityHint("Please wait while the app checks microphone permission status")
                }
            }
            .navigationTitle("Voice Recorder")
            .accessibilityAddTraits(.isHeader)
            .onAppear {
                // Assign model context and re-setup recorder when view appears
                if recorder.modelContext == nil {
                    recorder.modelContext = modelContext
                }
                recorder.setup()
            }
        }
    }
}
