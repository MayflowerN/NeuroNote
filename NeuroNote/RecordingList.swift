//
//  RecordingList.swift
//  NeuroNote
//
//  Created by Ellie on 7/2/25.
//

import SwiftUI

struct RecordingList: View {
    @Bindable var Recorder: Recorder
    var body: some View {
        List {
            ForEach(Recorder.recordings, id: \.createdAt) { recording in
                RecordingRow(audioURL: recording.fileURL)
            }
        }
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
//#Preview {
//    RecordingList()
//}
