//
//  Recorder.swift
//  NeuroNote
//
//  Created by Ellie on 7/1/25.
//

import AVFoundation
import SwiftData
import Speech

@Observable
class Recorder {
    enum RecordingState {
        case recording, paused, stopped
    }
    var audioLevel: Float = -120.0
    private var currentSegmentURL: URL!
    private var recordingFile: AVAudioFile?
    private var segmentTimer: Timer?
    private var recordingStartTime: Date?
    private var fileSegmentIndex: Int = 0
    private var inputFormat: AVAudioFormat!
    
    var speechRecognizer: SpeechRecognizer?
    
    private var engine: AVAudioEngine!
    private var state: RecordingState = .stopped
    
    var recordings = [Recording]()
    var recording = false
    var isReady = false
    
    fileprivate var isInterrupted = false
    fileprivate var configChangePending = false
    fileprivate var routeChangeNotification = false
    
    var modelContext: ModelContext?

    var sampleRate: Double = 44100.0
    var bitDepth: AVAudioCommonFormat = .pcmFormatInt16
    var numChannels: AVAudioChannelCount = 1
    init(modelContext: ModelContext? = nil, speechRecognizer: SpeechRecognizer? = nil) {
        self.modelContext = modelContext
        self.speechRecognizer = speechRecognizer
        AVAudioSession.sharedInstance().requestRecordPermission { granted in
            DispatchQueue.main.async {
                if granted {
                    self.setupSession()
                    self.setupEngine()
                    self.registerForNotifications()
                    self.isReady = true
                } else {
                    print("❌ Microphone permission denied.")
                }
            }
        }
    }
    fileprivate func setupSession() {
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker, .allowBluetooth])
        try? session.setPreferredSampleRate(44100) // Safe standard
        try? session.setActive(true, options: .notifyOthersOnDeactivation)
    }
    fileprivate func setupEngine() {
        engine = AVAudioEngine()

        let inputNode = engine.inputNode
        let silentMixer = AVAudioMixerNode()
        silentMixer.volume = 0.0 // ✅ prevent speaker feedback

        engine.attach(silentMixer)

        let format = inputNode.inputFormat(forBus: 0)
        engine.connect(inputNode, to: silentMixer, format: format)

        engine.prepare()
    }
    fileprivate func makeConnections() {
        let inputNode = engine.inputNode
        inputFormat = inputNode.outputFormat(forBus: 0) // Save it

        //engine.connect(inputNode, to: mixerNode, format: inputFormat)

//        let mainMixerNode = engine.mainMixerNode
//        engine.connect(mixerNode, to: mainMixerNode, format: inputFormat) // use same format
    }
    func startRecording() throws {
        guard !recording else { return }

        try AVAudioSession.sharedInstance().setActive(true, options: [.notifyOthersOnDeactivation])

        let inputNode = engine.inputNode
        let inputHWFormat = inputNode.inputFormat(forBus: 0) // ✅ Matches mic format

        // ✅ Configurable file format (can differ from tap)
        let outputFormat = AVAudioFormat(
            commonFormat: bitDepth,
            sampleRate: sampleRate,
            channels: numChannels,
            interleaved: false
        )!

        currentSegmentURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".caf")
        print("💾 Saved to: \(currentSegmentURL.absoluteString)")
        recordingFile = try AVAudioFile(forWriting: currentSegmentURL, settings: outputFormat.settings)

        inputNode.removeTap(onBus: 0)

        // ✅ Use input hardware format for tap
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: inputHWFormat) { [weak self] buffer, _ in
            guard let self = self else { return }
            if let channelData = buffer.floatChannelData?[0] {
                let frameLength = Int(buffer.frameLength)
                
                let bufferPointer = UnsafeBufferPointer(start: channelData, count: frameLength)
                let squaredSamples = bufferPointer.map { $0 * $0 }
                let meanSquare = squaredSamples.reduce(0, +) / Float(frameLength)
                let rms = sqrt(meanSquare)
                
                let avgPower = 20 * log10(rms)

                DispatchQueue.main.async {
                    self.audioLevel = avgPower.isFinite ? avgPower : -120.0
                }
            }          // 🔄 If format mismatch, convert buffer to outputFormat before writing
            if buffer.format != self.recordingFile?.processingFormat {
                let converter = AVAudioConverter(from: buffer.format, to: self.recordingFile!.processingFormat)!
                let pcmBuffer = AVAudioPCMBuffer(pcmFormat: self.recordingFile!.processingFormat, frameCapacity: buffer.frameCapacity)!
                var error: NSError? = nil
                let inputBlock: AVAudioConverterInputBlock = { _, outStatus in
                    outStatus.pointee = .haveData
                    return buffer
                }
                converter.convert(to: pcmBuffer, error: &error, withInputFrom: inputBlock)
                try? self.recordingFile?.write(from: pcmBuffer)
            } else {
                try? self.recordingFile?.write(from: buffer)
            }
        }

        try engine.start()

        state = .recording
        recording = true
        scheduleNextSegment()
    }
    private func scheduleNextSegment() {
        segmentTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            try? self?.rotateSegment()
        }
    }

    private func rotateSegment() throws {
        engine.inputNode.removeTap(onBus: 0)
        try saveCurrentSegment()

        fileSegmentIndex += 1
        try startRecording() // recursively start next segment
    }
    private func saveCurrentSegment() throws {
        guard let file = recordingFile else { return }
        let savedURL = file.url
        let now = Date()

        if let context = modelContext {
            let recording = Recording(fileURL: savedURL, createdAt: now)
            context.insert(recording)

            let segment = TranscriptionSegment(audioURL: savedURL, createdAt: now, status: .pending, attemptCount: 0, parent: recording)
            context.insert(segment)

            try? context.save()

            // ✅ Move this *inside* so `segment` and `context` are in scope
            speechRecognizer?.transcribeAudioFile(at: savedURL, for: segment, in: context)
        }

        print("✅ Final segment saved to: \(savedURL.absoluteString)")
        recordingFile = nil
    }
    func resumeRecording() throws {
        try engine.start()
        state = .recording
    }
    
    func pauseRecording() {
        engine.pause()
        state = .paused
    }
    func stopRecording() {
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        segmentTimer?.invalidate()
        try? saveCurrentSegment()
        state = .stopped
        recording = false
    }
    fileprivate func registerForNotifications() {
        NotificationCenter.default.addObserver(
            forName: AVAudioSession.interruptionNotification,
            object: nil,
            queue: nil
        )
        { [weak self] (notification) in
            guard let weakself = self else {
                return
            }
            
            let userInfo = notification.userInfo
            let interruptionTypeValue: UInt = userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt ?? 0
            let interruptionType = AVAudioSession.InterruptionType(rawValue: interruptionTypeValue)!
            
            switch interruptionType {
            case .began:
                weakself.isInterrupted = true
                
                if weakself.state == .recording {
                    weakself.pauseRecording()
                }
            case .ended:
                weakself.isInterrupted = false

                // Check if the system recommends resuming audio
                if let optionsValue = userInfo?[AVAudioSessionInterruptionOptionKey] as? UInt {
                    let options = AVAudioSession.InterruptionOptions(rawValue: optionsValue)
                    if options.contains(.shouldResume), weakself.state == .paused {
                        try? AVAudioSession.sharedInstance().setActive(true, options: .notifyOthersOnDeactivation)
                        try? weakself.resumeRecording()
                    }
                }
            @unknown default:
                break
            }
        }
        NotificationCenter.default.addObserver(
            forName: Notification.Name.AVAudioEngineConfigurationChange,
            object: nil,
            queue: nil
        ) { [weak self] (notification) in
            guard let weakself = self else {
                return
            }
            
            weakself.configChangePending = true
            
            if (!weakself.isInterrupted) {
                weakself.handleConfigurationChange()
            } else {
                print("deferring changes")
            }
        }
        NotificationCenter.default.addObserver(
            forName: AVAudioSession.mediaServicesWereResetNotification,
            object: nil,
            queue: nil
        ) { [weak self] (notification) in
            guard let weakself = self else {
                return
            }
            
            weakself.setupSession()
            weakself.setupEngine()
        }
        NotificationCenter.default.addObserver(
            forName: AVAudioSession.routeChangeNotification,
            object: nil,
            queue: nil
        ) { [weak self] notification in
            guard let self = self else { return }
            // Optional: check reason
            if let reasonValue = notification.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt,
               let reason = AVAudioSession.RouteChangeReason(rawValue: reasonValue) {
                switch reason {
                case .oldDeviceUnavailable:
                    print("Mic or headphones unplugged")
                    self.pauseRecording()
                case .newDeviceAvailable:
                    print("New mic or headphones plugged in")
                    // Optional: resume or update UI
                default:
                    break
                }
            }
        }
    }
    
    fileprivate func handleConfigurationChange() {
        if configChangePending {
            makeConnections()
        }
        
        configChangePending = false
    }
    func setup() {
        AVAudioSession.sharedInstance().requestRecordPermission { granted in
            DispatchQueue.main.async {
                if granted {
                    self.setupSession()
                    self.setupEngine()
                    self.registerForNotifications()
                } else {
                    print("❌ Microphone permission denied.")
                }
            }
        }
    }
}

