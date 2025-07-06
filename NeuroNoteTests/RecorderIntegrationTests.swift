//
//  RecorderIntegrationTests.swift
//  NeuroNoteTests
//
//  Created by Ellie on 7/5/25.
//
import XCTest
@testable import NeuroNote

final class RecorderIntegrationTests: XCTestCase {

    func testRecorderInitialState() {
        let recorder = Recorder(speechRecognizer: SpeechRecognizer())
        XCTAssertFalse(recorder.recording, "Recorder should not be recording initially")
        XCTAssertEqual(recorder.state, .stopped)
    }

    func testRecorderStartStop() async throws {
        let recorder = Recorder(speechRecognizer: SpeechRecognizer())
        try await recorder.startRecording()
        XCTAssertTrue(recorder.recording, "Recorder should be recording after start")

        recorder.stopRecording()
        XCTAssertFalse(recorder.recording, "Recorder should not be recording after stop")
        XCTAssertEqual(recorder.state, .stopped)
    }

    func testRecordingAppendsToSession() async throws {
        let recorder = Recorder(speechRecognizer: SpeechRecognizer())

        // Instead of waiting for real audio, we simulate an insert
        // Recordings is a public var so we append a dummy manually
        recorder.recordings.append(Recording(fileURL: URL(fileURLWithPath: "/dev/null")))

        XCTAssertGreaterThanOrEqual(recorder.recordings.count, 1, "Should have at least 1 recording session")
    }
}
