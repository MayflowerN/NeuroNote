//
//  RecordingList.swift
//  NeuroNote
//
//  Created by Ellie on 7/2/25.
//

import SwiftUI
import SwiftData

// Displays a list of recordings sorted by most recent
struct RecordingList: View {
    var recordings: [Recording]
    @Environment(\.modelContext) var context

    var body: some View {
        List {
            ForEach(recordings) { recording in
                NavigationLink {
                    SegmentListView(recording: recording)
                } label: {
                    VStack(alignment: .leading) {
                        Text("Recording: \(recording.createdAt.formatted(date: .abbreviated, time: .shortened))")
                        Text("\(recording.segments.count) segments")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("Recording from \(recording.createdAt.formatted(date: .abbreviated, time: .shortened)), with \(recording.segments.count) segments")
                    .accessibilityHint("Tap to view transcription segments")
                }
            }
            .onDelete(perform: deleteRecording) // Enables swipe to delete
        }
        .accessibilityLabel("Recordings List")
        .accessibilityHint("Swipe to delete recordings")
    }

    /// Deletes the selected recording and its associated file from disk
    private func deleteRecording(at offsets: IndexSet) {
        for index in offsets {
            let recording = recordings[index]

            // Delete the file from disk if it exists
            if FileManager.default.fileExists(atPath: recording.fileURL.path) {
                do {
                    try FileManager.default.removeItem(at: recording.fileURL)
                    print("🗑️ Deleted file: \(recording.fileURL.lastPathComponent)")
                } catch {
                    print("⚠️ Failed to delete file: \(error.localizedDescription)")
                }
            }

            // Remove recording from SwiftData
            context.delete(recording)
        }

        // Save context after deletion
        do {
            try context.save()
        } catch {
            print("❌ Failed to save context after deletion: \(error.localizedDescription)")
        }
    }
}

// Displays the list of transcription segments for a selected recording
struct SegmentListView: View {
    var recording: Recording

    var body: some View {
        List {
            ForEach(recording.segments) { segment in
                VStack(alignment: .leading) {
                    Text(segment.transcriptionText ?? "Transcription: (pending)")
                        .font(.body)

                    HStack {
                        Text("Status: \(segment.status.rawValue.capitalized)")
                        Spacer()
                        Text(segment.createdAt.formatted(date: .omitted, time: .shortened))
                            .foregroundColor(.secondary)
                    }
                    .font(.footnote)
                }
                .padding(.vertical, 4)
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Segment created at \(segment.createdAt.formatted(date: .omitted, time: .shortened)). Status: \(segment.status.rawValue.capitalized). \(segment.transcriptionText ?? "Transcription pending")")
            }
        }
        .navigationTitle("Segments")
        .accessibilityLabel("Transcription Segments")
        .accessibilityHint("Displays list of transcribed audio segments")
    }
}

// Shows a single row of audio file (not currently used)
struct RecordingRow: View {
    var audioURL: URL

    var body: some View {
        HStack {
            Text(audioURL.lastPathComponent)
            Spacer()
        }
        .accessibilityElement()
        .accessibilityLabel("Audio file \(audioURL.lastPathComponent)")
    }
}

