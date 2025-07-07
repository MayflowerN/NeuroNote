//
//  Recorder.swift
//  NeuroNote
//
//  Created by Ellie on 7/1/25.
//

import AVFoundation
import SwiftData
import Speech

enum RecorderError: Error {
    case insufficientDiskSpace
    case microphonePermissionDenied
}

@Observable
class Recorder {
    enum RecordingState {
        case recording, paused, stopped
    }

    // MARK: - Public State
    var microphonePermissionGranted: Bool? = nil
    var audioLevel: Float = -120.0
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

    /// Initializes the Recorder and sets up audio session and engine if microphone permission is granted.
    init(modelContext: ModelContext? = nil, speechRecognizer: SpeechRecognizer? = nil) {
        self.modelContext = modelContext
        self.speechRecognizer = speechRecognizer

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

    /// Configures the AVAudioSession for recording.
    private func setupSession() {
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker, .allowBluetooth])
        try? session.setPreferredSampleRate(sampleRate)
        try? session.setActive(true, options: .notifyOthersOnDeactivation)
    }

    /// Prepares the AVAudioEngine with a silent mixer.
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

    /// Captures the input format of the audio input node.
    private func makeConnections() {
        let inputNode = engine.inputNode
        inputFormat = inputNode.outputFormat(forBus: 0)
    }

    /// Checks if there's enough free disk space.
    private func isDiskSpaceAvailable(minimumFreeMB: Int = 10) -> Bool {
        let fileURL = FileManager.default.temporaryDirectory
        if let values = try? fileURL.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]),
           let available = values.volumeAvailableCapacityForImportantUsage {
            return available > Int64(minimumFreeMB * 1024 * 1024)
        }
        return false
    }

    /// Begins recording audio and writing to a .caf file.
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

            currentSegmentURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".caf")
            recordingFile = try AVAudioFile(forWriting: currentSegmentURL, settings: outputFormat.settings)

            inputNode.removeTap(onBus: 0)
            inputNode.installTap(onBus: 0, bufferSize: 1024, format: inputHWFormat) { [weak self] buffer, _ in
                self?.writeBuffer(buffer)
            }

            try engine.start()
            state = .recording
            recording = true
            scheduleNextSegment()
        } catch {
            throw error
        }
    }

    /// Writes an incoming buffer to the current audio file.
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
            DispatchQueue.main.async { self.stopRecording() }
        }
    }

    /// Sets up a timer to rotate segments every 30 seconds.
    private func scheduleNextSegment() {
        segmentTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            try? self?.rotateSegment()
        }
    }

    /// Ends current segment and starts a new one.
    private func rotateSegment() throws {
        engine.inputNode.removeTap(onBus: 0)
        try saveCurrentSegment()
        fileSegmentIndex += 1
        try startRecording()
    }

    /// Saves the current audio segment to SwiftData and triggers transcription.
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

            speechRecognizer?.transcribeAudioFile(at: savedURL, for: segment, in: context)
        }

        print("Segment saved: \(savedURL.lastPathComponent)")
        recordingFile = nil
    }

    /// Stops the engine, saves the last segment, and resets recording state.
    func stopRecording() {
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        segmentTimer?.invalidate()
        try? saveCurrentSegment()

        state = .stopped
        recording = false
    }

    /// Pauses the audio engine.
    func pauseRecording() {
        engine.pause()
        state = .paused
    }

    /// Resumes the audio engine.
    func resumeRecording() throws {
        try engine.start()
        state = .recording
    }

    /// Registers for AVAudioSession and AVAudioEngine notifications.
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

    /// Handles AVAudioSession interruptions.
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

    /// Handles audio route changes (e.g. headphones unplugged).
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

    /// Applies pending configuration updates.
    private func handleConfigurationChange() {
        if configChangePending {
            makeConnections()
            configChangePending = false
        }
    }

    /// Manually triggers session setup again.
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
