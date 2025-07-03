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
    private var engine: AVAudioEngine!
    private var mixerNode: AVAudioMixerNode!
    private var state: RecordingState = .stopped
    
    var recordings = [Recording]()
    var recording = false
    
    var compressedBuffer: AVAudioCompressedBuffer?
    
    fileprivate var isInterrupted = false
    fileprivate var configChangePending = false
    fileprivate var routeChangeNotification = false
    
    var modelContext: ModelContext?
    private var converter: AVAudioConverter?
    init(modelContext: ModelContext? = nil) {
        self.modelContext = modelContext
        setupSession()
        setupEngine()
        registerForNotifications()
    }
    fileprivate func setupSession() {
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.record)
        try? session.setActive(true, options: .notifyOthersOnDeactivation)
    }
    fileprivate func setupEngine() {
        engine = AVAudioEngine()
        mixerNode = AVAudioMixerNode()
        
        // Set volume to 0 to avoid audio feedback while recording.
        mixerNode.volume = 0
        
        engine.attach(mixerNode)
        
        makeConnections()
        
        // Prepare the engine in advance, in order for the system to allocate the necessary resources.
        engine.prepare()
    }
    
    fileprivate func makeConnections() {
        let inputNode = engine.inputNode
        let inputFormat = inputNode.outputFormat(forBus: 0)
        engine.connect(inputNode, to: mixerNode, format: inputFormat)
        
        let mainMixerNode = engine.mainMixerNode
        let mixerFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: inputFormat.sampleRate, channels: 1, interleaved: false)
        engine.connect(mixerNode, to: mainMixerNode, format: mixerFormat)
    }
   
    func startRecording() throws {
        let tapNode: AVAudioNode = mixerNode
        let format = tapNode.outputFormat(forBus: 0)
      
        var outDesc = AudioStreamBasicDescription()
        outDesc.mSampleRate = format.sampleRate
        outDesc.mChannelsPerFrame = 1
        outDesc.mFormatID = kAudioFormatMPEG4AAC
        
        let framesPerPacket: UInt32 = 1152
        outDesc.mFramesPerPacket = framesPerPacket
        outDesc.mBitsPerChannel = 24
        outDesc.mBytesPerPacket = 0
        
        let convertFormat = AVAudioFormat(streamDescription: &outDesc)!
        self.converter = AVAudioConverter(from: format, to: convertFormat)
        
        let packetSize: UInt32 = 8
        let bufferSize = framesPerPacket * packetSize
        
        tapNode.installTap(onBus: 0, bufferSize: bufferSize, format: format) { [weak self] buffer, time in
            guard let self = self, let converter = self.converter else { return }
            let compressedBuffer = AVAudioCompressedBuffer(
                format: convertFormat,
                packetCapacity: packetSize,
                maximumPacketSize: converter.maximumOutputPacketSize
            )
            let inputBlock: AVAudioConverterInputBlock = { _, outStatus in
                outStatus.pointee = .haveData
                return buffer
            }

            var outError: NSError?
            converter.convert(to: compressedBuffer, error: &outError, withInputFrom: inputBlock)

            if let error = outError {
                print("❌ Conversion error: \(error.localizedDescription)")
                return
            }

            self.compressedBuffer = compressedBuffer
            self.saveRecording(from: compressedBuffer)
        }
        
        try engine.start()
        state = .recording
    }
    
    private func saveRecording(from buffer: AVAudioCompressedBuffer) {
        let audioBuffer = buffer.audioBufferList.pointee.mBuffers
        guard let mData = audioBuffer.mData else {
            print("⚠️ No data to save")
            return
        }

        let length = Int(audioBuffer.mDataByteSize)
        let data = NSData(bytes: mData, length: length)
        let filename = UUID().uuidString + ".m4a"
        let fileURL = FileManager.default.temporaryDirectory.appendingPathComponent(filename)

        do {
            try data.write(to: fileURL)
            print("✅ Saved audio to: \(fileURL.path)")

            if let context = modelContext {
                let newRecording = Recording(fileURL: fileURL, createdAt: Date())
                context.insert(newRecording)
                try? context.save()
            }
        } catch {
            print("❌ Save error: \(error.localizedDescription)")
        }
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
        mixerNode.removeTap(onBus: 0)
        engine.stop()
        converter?.reset()
        state = .stopped
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
}

