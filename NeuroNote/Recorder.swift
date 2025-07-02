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
    
    var converter: AVAudioConverter!
    var compressedBuffer: AVAudioCompressedBuffer?
    
    fileprivate var isInterrupted = false
    fileprivate var configChangePending = false
    fileprivate var routeChangeNotification = false
    
    private var modelContext: ModelContext?
    init() {
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
        outDesc.mFormatID = kAudioFormatFLAC
        
        let framesPerPacket: UInt32 = 1152
        outDesc.mFramesPerPacket = framesPerPacket
        outDesc.mBitsPerChannel = 24
        outDesc.mBytesPerPacket = 0
        
        let convertFormat = AVAudioFormat(streamDescription: &outDesc)!
        converter = AVAudioConverter(from: format, to: convertFormat)
        
        let packetSize: UInt32 = 8
        let bufferSize = framesPerPacket * packetSize
        
        tapNode.installTap(onBus: 0, bufferSize: bufferSize, format: format, block: {
            [weak self] (buffer, time) in
            guard let weakself = self else {
                return
            }
            
            weakself.compressedBuffer = AVAudioCompressedBuffer(
                format: convertFormat,
                packetCapacity: packetSize,
                maximumPacketSize: weakself.converter.maximumOutputPacketSize
            )
            
            // input block is called when the converter needs input
            let inputBlock : AVAudioConverterInputBlock = { (inNumPackets, outStatus) -> AVAudioBuffer? in
                outStatus.pointee = AVAudioConverterInputStatus.haveData;
                return buffer; // fill and return input buffer
            }
            
            // Conversion loop
            var outError: NSError? = nil
            weakself.converter.convert(to: weakself.compressedBuffer!, error: &outError, withInputFrom: inputBlock)
            
            let audioBuffer = weakself.compressedBuffer!.audioBufferList.pointee.mBuffers
            if let mData = audioBuffer.mData {
                let length = Int(audioBuffer.mDataByteSize)
                let data = NSData(bytes: mData, length: length)

                // 1. Generate file path
                let filename = UUID().uuidString + ".flac" // or ".caf", ".m4a", etc.
                let fileURL = FileManager.default.temporaryDirectory.appendingPathComponent(filename)

                // 2. Write audio data to disk
                do {
                    try data.write(to: fileURL)
                    
                    // 3. Create a new SwiftData Recording object
                    let newRecording = Recording(fileURL: fileURL, createdAt: Date())

                    // 4. Insert into SwiftData
                    // You’ll need to inject the SwiftData model context here — example:
                    if let context = self.modelContext {
                        context.insert(newRecording)
                        try? context.save()
                    }

                    print("Saved recording at: \(fileURL.path)")
                } catch {
                    print("❌ Failed to write audio file: \(error.localizedDescription)")
                }
            }
            else {
                print("error")
            }
        })
        
        try engine.start()
        state = .recording
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
        converter.reset()
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

