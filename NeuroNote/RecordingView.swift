//
//  RecordingView.swift
//  NeuroNote
//
//  Created by Ellie on 7/2/25.
//
import SwiftUI
import SwiftData

struct RecordingView: View {
    @State var recorder: Recorder
    @Query var recordings: [Recording]

    @Environment(\.modelContext) var modelContext

    var body: some View {
        NavigationStack {
            VStack {
                if let permission = recorder.microphonePermissionGranted {
                    if permission {
                        RecordingList()
                        AudioLevelMeter(level: recorder.audioLevel)

                        if recorder.recording == false {
                            Button(action: {
                                if recorder.isReady {
                                    do {
                                        try recorder.startRecording()
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
                        } else {
                            Button(action: {
                                recorder.stopRecording()
                                print("All saved recordings:")
                                recordings.forEach { print($0.fileURL.absoluteString) }
                            }) {
                                Image(systemName: "stop.fill")
                                    .resizable()
                                    .frame(width: 100, height: 100)
                                    .foregroundColor(.red)
                                    .padding(.bottom, 40)
                            }
                        }
                    } else {
                        // Fallback UI if permission denied
                        VStack(spacing: 16) {
                            Image(systemName: "mic.slash")
                                .resizable()
                                .frame(width: 60, height: 80)
                                .foregroundColor(.gray)

                            Text("Microphone access is required to record.")
                                .multilineTextAlignment(.center)
                                .padding(.horizontal)

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
                        }
                        .padding()
                    }
                } else {
                    // show loading state while permission is undetermined
                    ProgressView("Checking microphone access...")
                        .padding()
                }
            }
            .navigationTitle("Voice Recorder")
            .onAppear {
                if recorder.modelContext == nil {
                    recorder.modelContext = modelContext
                }
                recorder.setup()
            }
        }
    }
}
