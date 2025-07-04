//
//  RecordingList.swift
//  NeuroNote
//
//  Created by Ellie on 7/2/25.
//

import SwiftUI
import SwiftData
struct RecordingList: View {
    @Query(sort: \Recording.createdAt, order: .reverse) var recordings: [Recording]
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
                 }
             }
             .onDelete(perform: deleteRecording)
         }
     }
    private func deleteRecording(at offsets: IndexSet) {
        for index in offsets {
            let recording = recordings[index]

            // Optionally delete audio file from disk
            try? FileManager.default.removeItem(at: recording.fileURL)

            context.delete(recording)
        }
        try? context.save()
    }
}
 
import SwiftUI

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
            }
        }
        .navigationTitle("Segments")
    }
}
struct RecordingRow: View {
    
    var audioURL: URL
    
    var body: some View {
        HStack {
            Text("\(audioURL.lastPathComponent)")
            Spacer()
        }
    }
}
struct AudioLevelMeter: View {
    var level: Float  // from Recorder.audioLevel

    var body: some View {
        let normalized = max(0, min(1, (level + 80) / 80)) // Normalize -80...0dB → 0...1
        let barHeight = CGFloat(normalized) * 100

        return VStack(spacing: 4) {
            RoundedRectangle(cornerRadius: 4)
                .fill(Color.green)
                .frame(width: 12, height: barHeight)
                .animation(.easeOut(duration: 0.1), value: barHeight)

            Text(String(format: "%.0f dB", level))
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(height: 120)
    }
}
//#Preview {
//    RecordingList()
//}
