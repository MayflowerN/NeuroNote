//
//  Recorder.swift
//  NeuroNote
//
//  Created by Ellie on 7/1/25.
//

import AVFoundation
import SwiftData
import Speech

/// Custom errors for recording edge cases.
enum RecorderError: Error {
    case insufficientDiskSpace
    case microphonePermissionDenied
}

/// Observable class that manages audio recording, segmentation, and transcription.
@Observable
class Recorder {
    enum RecordingState {
        case recording, paused, stopped
    }

    // MARK: - Public State
    var microphonePermissionGranted: Bool? = nil
    var isReady = false
    private(set) var recording = false
    var recordings = [Recording]()

    // MARK: - Private Properties
    private var currentSegmentURL: URL!
    private var recordingFile: AVAudioFile?
    private var segmentTimer: Timer?
    private var fileSegmentIndex: Int = 0
    private var inputFormat: AVAudioFormat!

    private var engine: AVAudioEngine!
    private(set) var state: RecordingState = .stopped

    private var isInterrupted = false
    private var configChangePending = false

    var speechRecognizer: SpeechRecognizer?
    var modelContext: ModelContext?

    var sampleRate: Double = 44100.0
    var bitDepth: AVAudioCommonFormat = .pcmFormatInt16
    var numChannels: AVAudioChannelCount = 1

    /// Initializes the recorder and prepares audio session and engine if permission is granted.
    init(modelContext: ModelContext? = nil, speechRecognizer: SpeechRecognizer? = nil) {
        self.modelContext = modelContext
        self.speechRecognizer = speechRecognizer

        // Request microphone access from user
        AVAudioSession.sharedInstance().requestRecordPermission { granted in
            DispatchQueue.main.async {
                self.microphonePermissionGranted = granted
                if granted {
                    self.setupSession()
                    self.setupEngine()
                    self.registerForNotifications()
                    self.isReady = true
                } else {
                    print("Microphone permission denied.")
                }
            }
        }
    }

    /// Configures AVAudioSession for dual-purpose (record + play) and enables speaker + Bluetooth.
    private func setupSession() {
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker, .allowBluetooth])
        try? session.setPreferredSampleRate(sampleRate)
        try? session.setActive(true, options: .notifyOthersOnDeactivation)
    }

    /// Sets up AVAudioEngine to capture audio via a silent mixer node.
    private func setupEngine() {
        engine = AVAudioEngine()
        let inputNode = engine.inputNode
        let silentMixer = AVAudioMixerNode()
        silentMixer.volume = 0.0

        engine.attach(silentMixer)
        let format = inputNode.inputFormat(forBus: 0)
        engine.connect(inputNode, to: silentMixer, format: format)

        engine.prepare()
    }

    /// Refreshes the input format after engine reset or route change.
    private func makeConnections() {
        let inputNode = engine.inputNode
        inputFormat = inputNode.outputFormat(forBus: 0)
    }

    /// Verifies disk has enough space for audio recording to proceed.
    private func isDiskSpaceAvailable(minimumFreeMB: Int = 10) -> Bool {
        let fileURL = FileManager.default.temporaryDirectory
        if let values = try? fileURL.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]),
           let available = values.volumeAvailableCapacityForImportantUsage {
            return available > Int64(minimumFreeMB * 1024 * 1024)
        }
        return false
    }

    /// Starts recording a new segment and sets up audio tap.
    func startRecording() throws {
        guard !recording else { return }
        guard isDiskSpaceAvailable() else {
            throw RecorderError.insufficientDiskSpace
        }

        do {
            try AVAudioSession.sharedInstance().setActive(true, options: [.notifyOthersOnDeactivation])

            let inputNode = engine.inputNode
            let inputHWFormat = inputNode.inputFormat(forBus: 0)
            let outputFormat = AVAudioFormat(
                commonFormat: bitDepth,
                sampleRate: sampleRate,
                channels: numChannels,
                interleaved: false
            )!

            // Generate file path and open audio file for writing
            currentSegmentURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".caf")
            recordingFile = try AVAudioFile(forWriting: currentSegmentURL, settings: outputFormat.settings)

            // Attach tap to continuously write PCM buffers
            inputNode.removeTap(onBus: 0)
            inputNode.installTap(onBus: 0, bufferSize: 1024, format: inputHWFormat) { [weak self] buffer, _ in
                self?.writeBuffer(buffer)
            }
            if !engine.isRunning {
                try engine.start()
            }
            state = .recording
            recording = true
            scheduleNextSegment()
        } catch {
            throw error
        }
    }

    /// Handles writing buffer data to the AVAudioFile, performing format conversion if needed.
    private func writeBuffer(_ buffer: AVAudioPCMBuffer) {
        guard let file = recordingFile else { return }

        do {
            if buffer.format != file.processingFormat {
                let converter = AVAudioConverter(from: buffer.format, to: file.processingFormat)!
                let pcmBuffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: buffer.frameCapacity)!
                var error: NSError? = nil

                let inputBlock: AVAudioConverterInputBlock = { _, outStatus in
                    outStatus.pointee = .haveData
                    return buffer
                }

                converter.convert(to: pcmBuffer, error: &error, withInputFrom: inputBlock)
                try file.write(from: pcmBuffer)
            } else {
                try file.write(from: buffer)
            }
        } catch {
            // Stop recording on any file write error
            DispatchQueue.main.async { self.stopRecording() }
        }
    }

    /// Creates a timer to automatically rotate to new segments every 30 seconds.
    private func scheduleNextSegment() {
        segmentTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            try? self?.rotateSegment()
        }
    }

    /// Ends the current segment and starts a new one by restarting recording.
    private func rotateSegment() throws {
        engine.inputNode.removeTap(onBus: 0)
        try saveCurrentSegment()
        fileSegmentIndex += 1
        try startRecording()
    }

    /// Saves current segment metadata and triggers transcription.
    private func saveCurrentSegment() throws {
        guard let file = recordingFile else { return }

        let savedURL = file.url
        let now = Date()

        if let context = modelContext {
            let recording = Recording(fileURL: savedURL, createdAt: now)
            let segment = TranscriptionSegment(audioURL: savedURL, createdAt: now, status: .pending, attemptCount: 0, parent: recording)

            context.insert(recording)
            context.insert(segment)
            try? context.save()

            // Trigger backend or local transcription
            speechRecognizer?.transcribeAudioFile(at: savedURL, for: segment, in: context)
        }

        print("Segment saved: \(savedURL.lastPathComponent)")
        recordingFile = nil
    }

    /// Stops the audio engine and timer, saves last segment.
    func stopRecording() {
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        segmentTimer?.invalidate()
        try? saveCurrentSegment()

        state = .stopped
        recording = false
    }

    /// Temporarily pauses the audio engine.
    func pauseRecording() {
        engine.pause()
        state = .paused
    }

    /// Resumes the audio engine from a paused state.
    func resumeRecording() throws {
        try engine.start()
        state = .recording
    }

    /// Observes AVAudioSession and AVAudioEngine system notifications.
    private func registerForNotifications() {
        let center = NotificationCenter.default

        center.addObserver(forName: AVAudioSession.interruptionNotification, object: nil, queue: nil) { [weak self] notif in
            self?.handleInterruption(notif)
        }

        center.addObserver(forName: .AVAudioEngineConfigurationChange, object: nil, queue: nil) { [weak self] _ in
            self?.configChangePending = true
            if self?.isInterrupted == false {
                self?.handleConfigurationChange()
            }
        }

        center.addObserver(forName: AVAudioSession.mediaServicesWereResetNotification, object: nil, queue: nil) { [weak self] _ in
            self?.setupSession()
            self?.setupEngine()
        }

        center.addObserver(forName: AVAudioSession.routeChangeNotification, object: nil, queue: nil) { [weak self] notif in
            self?.handleRouteChange(notif)
        }
    }

    /// Handles Siri, calls, and other interruptions during recording.
    private func handleInterruption(_ notification: Notification) {
        guard let typeValue = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: typeValue) else { return }

        switch type {
        case .began:
            isInterrupted = true
            if state == .recording { pauseRecording() }
        case .ended:
            isInterrupted = false
            if let optionsValue = notification.userInfo?[AVAudioSessionInterruptionOptionKey] as? UInt,
               AVAudioSession.InterruptionOptions(rawValue: optionsValue).contains(.shouldResume),
               state == .paused {
                try? AVAudioSession.sharedInstance().setActive(true)
                try? resumeRecording()
            }
        default: break
        }
    }

    /// Handles hardware route changes like plugging/unplugging headphones.
    private func handleRouteChange(_ notification: Notification) {
        guard let reasonValue = notification.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt,
              let reason = AVAudioSession.RouteChangeReason(rawValue: reasonValue) else { return }

        switch reason {
        case .oldDeviceUnavailable:
            pauseRecording()
        case .newDeviceAvailable:
            break
        default: break
        }
    }

    /// Rebuilds audio engine configuration when system signals changes.
    private func handleConfigurationChange() {
        if configChangePending {
            makeConnections()
            configChangePending = false
        }
    }

    /// Public method to reinitialize recorder if session reset.
    func setup() {
        AVAudioSession.sharedInstance().requestRecordPermission { granted in
            DispatchQueue.main.async {
                if granted {
                    self.setupSession()
                    self.setupEngine()
                    self.registerForNotifications()
                } else {
                    print("Microphone permission denied.")
                }
            }
        }
    }
}
