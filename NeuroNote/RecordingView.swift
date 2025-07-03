//
//  RecordingView.swift
//  NeuroNote
//
//  Created by Ellie on 7/2/25.
//

import SwiftUI
import SwiftData

struct RecordingView: View {
    @State var Recorder: Recorder
    @Query var recordings: [Recording]
    
    @Environment(\.modelContext) var modelContext
    var body: some View {
        NavigationStack {
            VStack {
                RecordingList(Recorder: Recorder)
                if Recorder.recording == false {
                    Button(action: {
                        if Recorder.isReady {
                            do {
                                try self.Recorder.startRecording()
                                self.Recorder.recording = true
                            } catch {
                                print("Failed to start recording: \(error.localizedDescription)")
                            }
                        } else {
                            print("❌ Recorder not ready yet. Microphone permission may still be pending.")
                        }
                    }) {
                        Image(systemName: "circle.fill")
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: 100, height: 100)
                            .clipped()
                            .foregroundColor(.red)
                            .padding(.bottom, 40)
                    }
                } else {
                    Button(action: {self.Recorder.stopRecording()}) {
                        Image(systemName: "stop.fill")
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: 100, height: 100)
                            .clipped()
                            .foregroundColor(.red)
                            .padding(.bottom, 40)
                    }
                }
            }
            .navigationTitle("Voice recorder")
            .onAppear {
                if Recorder.modelContext == nil {
                    Recorder.modelContext = modelContext
                }
                Recorder.setup()  
                
            }
        }
        
    }
    
}
//#Preview {
//    RecordingView()
//}
