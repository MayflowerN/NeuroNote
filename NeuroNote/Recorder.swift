//
//  Recorder.swift
//  NeuroNote
//
//  Created by Ellie on 7/1/25.
//

import AVFoundation
import SwiftData

@Observable
class Recorder {
    enum RecordingState {
        case recording, paused, stopped
    }
    private var currentSegmentURL: URL!
    private var recordingFile: AVAudioFile?
    private var segmentTimer: Timer?
    private var recordingStartTime: Date?
    private var fileSegmentIndex: Int = 0
    private var inputFormat: AVAudioFormat!
    
    private var engine: AVAudioEngine!
    private var state: RecordingState = .stopped
    
    var recordings = [Recording]()
    var recording = false
    
    
    fileprivate var isInterrupted = false
    fileprivate var configChangePending = false
    fileprivate var routeChangeNotification = false
    
    var modelContext: ModelContext?

    init(modelContext: ModelContext? = nil) {
        self.modelContext = modelContext
        registerForNotifications()
    }
    fileprivate func setupSession() {
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.record)
        try? session.setActive(true, options: .notifyOthersOnDeactivation)
    }
    fileprivate func setupEngine() {
        engine = AVAudioEngine()
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
        try AVAudioSession.sharedInstance().setActive(true, options: [.notifyOthersOnDeactivation])
        
        makeConnections()

        let inputNode = engine.inputNode
        let format = inputNode.outputFormat(forBus: 0)

        currentSegmentURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".caf")
        recordingFile = try AVAudioFile(forWriting: currentSegmentURL, settings: format.settings)

        inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            guard let self = self else { return }

            do {
                try self.recordingFile?.write(from: buffer)
            } catch {
                print("❌ Failed to write audio buffer: \(error)")
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

        if let context = modelContext {
            let newRecording = Recording(fileURL: savedURL, createdAt: Date())
            context.insert(newRecording)
            try? context.save()
        }

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
                
                // Activate session again
                try? AVAudioSession.sharedInstance().setActive(true, options: .notifyOthersOnDeactivation)
                
                weakself.handleConfigurationChange()
                
                if weakself.state == .paused {
                    try? weakself.resumeRecording()
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

