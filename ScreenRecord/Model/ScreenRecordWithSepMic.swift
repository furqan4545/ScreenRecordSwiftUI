//
//  ScreenRecordWithSepMic.swift
//  ScreenRecord
//
//  Created by Furqan Ali on 3/25/25.
//

import Foundation
import AVFoundation
import ScreenCaptureKit
import Combine
import Accelerate

/// Model class that handles screen recording functionality
class ScreenRecorderWithSepMic: NSObject, SCStreamDelegate, SCStreamOutput {
    
    // MARK: - Enums
    enum StreamType: Int {
        case screen, window, systemAudio
    }
    
    enum AudioQuality: Int {
        case normal = 128, good = 192, high = 256, extreme = 320
    }
    
    enum VideoFormat: String {
        case mov, mp4
    }
    
    enum RecorderState: Equatable {
        case idle
        case preparing
        case recording
        case error(Error)
        
        static func == (lhs: RecorderState, rhs: RecorderState) -> Bool {
            switch (lhs, rhs) {
            case (.idle, .idle),
                 (.preparing, .preparing),
                 (.recording, .recording):
                return true
            case (.error(let lhsError), .error(let rhsError)):
                return lhsError.localizedDescription == rhsError.localizedDescription
            default:
                return false
            }
        }
    }
    
    // MARK: - Properties
    private var availableContent: SCShareableContent?
    private var filter: SCContentFilter?
    private var screen: SCDisplay?
    private var audioSettings: [String: Any]!
    private var stream: SCStream?
    private var streamType: StreamType?
    private var vW: AVAssetWriter?
    private var recordMic = false
    private var vwInput, awInput, micInput: AVAssetWriterInput!
    private let audioEngine = AVAudioEngine()
    
    // Microphone writer
    private var micWriter: AVAssetWriter?
    private var micWriterInput: AVAssetWriterInput?
    
    // MARK: - Published Properties
    @Published var state: RecorderState = .idle
    @Published var displays: [SCDisplay] = []
    @Published var outputURL: URL?
    @Published var micOutputURL: URL?
    
    // MARK: - Initialization
    override init() {
        super.init()
        updateAudioSettings()
    }
    
    // MARK: - Public Methods
    func requestPermission() {
        SCShareableContent.getExcludingDesktopWindows(true, onScreenWindowsOnly: true) { [weak self] content, error in
            guard let self = self else { return }
            
            DispatchQueue.main.async {
                if let error = error {
                    switch error {
                    case SCStreamError.userDeclined:
                        print("User declined screen recording permission")
                        if let url = URL(string: "x-apple.systempreferences:com.apple.preferences.security?Privacy_ScreenCapture") {
                            NSWorkspace.shared.open(url)
                        }
                    default:
                        print("[Err] Failed to fetch available content: \(error.localizedDescription)")
                        self.state = .error(error)
                    }
                    return
                }
                
                self.availableContent = content
                self.displays = content?.displays ?? []
                
                // Debug info about available displays
                for (i, display) in self.displays.enumerated() {
                    let isMain = display.displayID == CGMainDisplayID()
                    let displayName = "Display \(i+1)\(isMain ? " (Main)" : "")"
                    print(displayName)
                }
                
                self.state = .idle
            }
        }
    }
    
    func requestMicrophonePermission(completion: @escaping (Bool) -> Void) {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            completion(true)
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .audio) { granted in
                DispatchQueue.main.async {
                    completion(granted)
                }
            }
        case .denied, .restricted:
            completion(false)
        default:
            completion(false)
        }
    }
    
    func startRecording() {
        guard state != .recording else { return }
        
        state = .preparing
        
        streamType = .screen
        
        if let firstDisplay = availableContent?.displays.first {
            screen = firstDisplay
            
            let excludedApps = availableContent?.applications.filter {
                Bundle.main.bundleIdentifier == $0.bundleIdentifier
            } ?? []
            
            filter = SCContentFilter(display: screen ?? firstDisplay,
                                       excludingApplications: excludedApps,
                                       exceptingWindows: [])
            
            Task {
                if let filter = filter {
                    await record(filter: filter)
                } else {
                    state = .error(NSError(domain: "ScreenRecorderError", code: 1, userInfo: ["message": "Failed to create content filter"]))
                }
            }
        } else {
            state = .error(NSError(domain: "ScreenRecorderError", code: 2, userInfo: ["message": "No display available"]))
        }
    }
    
    func stopRecording() {
        guard state == .recording, let stream = stream else { return }
        
        stream.stopCapture()
        self.stream = nil
        closeVideo()
        streamType = nil
        state = .idle
    }
    
    // MARK: - Private Methods
    private func updateAudioSettings() {
        audioSettings = [AVSampleRateKey: 48000, AVNumberOfChannelsKey: 2]
        audioSettings[AVFormatIDKey] = kAudioFormatMPEG4AAC
        audioSettings[AVEncoderBitRateKey] = AudioQuality.high.rawValue * 1000
    }
    
    private func record(filter: SCContentFilter) async {
        let conf = SCStreamConfiguration()
        
        conf.width = Int(filter.contentRect.width) * Int(filter.pointPixelScale)
        conf.height = Int(filter.contentRect.height) * Int(filter.pointPixelScale)
        conf.minimumFrameInterval = CMTime(value: 1, timescale: CMTimeScale(60))
        conf.showsCursor = true
        conf.capturesAudio = true
        conf.sampleRate = audioSettings["AVSampleRateKey"] as! Int
        conf.channelCount = audioSettings["AVNumberOfChannelsKey"] as! Int
        
        stream = SCStream(filter: filter, configuration: conf, delegate: self)
        
        do {
            if let stream = stream {
                try stream.addStreamOutput(self, type: .screen, sampleHandlerQueue: .global())
                try stream.addStreamOutput(self, type: .audio, sampleHandlerQueue: .global())
                initVideo(conf: conf)
                try await stream.startCapture()
                
                await MainActor.run {
                    self.state = .recording
                }
            }
        } catch {
            await MainActor.run {
                self.state = .error(error)
            }
            return
        }
    }
    
    private func initVideo(conf: SCStreamConfiguration) {
        let fileEnding = VideoFormat.mp4.rawValue
        var fileType: AVFileType?
        
        switch fileEnding {
        case VideoFormat.mov.rawValue: fileType = .mov
        case VideoFormat.mp4.rawValue: fileType = .mp4
        default: assertionFailure("Unknown video format")
        }
        
        if let downloadsDirectory = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first {
            let dateFormatter = DateFormatter()
            dateFormatter.dateFormat = "yyyy-MM-dd-HH-mm-ss"
            let dateString = dateFormatter.string(from: Date())
            let url = downloadsDirectory.appendingPathComponent("Recording-\(dateString).\(fileEnding)") // for main video
            let micUrl = downloadsDirectory.appendingPathComponent("Mic-Recording-\(dateString).wav") // for mic
            
            DispatchQueue.main.async {
                self.outputURL = url
                self.micOutputURL = micUrl
            }
            
            do {
                vW = try AVAssetWriter(outputURL: url, fileType: fileType!)
                
                // Microphone writer setup (WAV format)
                micWriter = try AVAssetWriter(outputURL: micUrl, fileType: .wav)
                
                let fpsMultiplier: Double = Double(60) / 8
                let encoderMultiplier: Double = 0.9
                let targetBitrate = (Double(conf.width) * Double(conf.height) * fpsMultiplier * encoderMultiplier)
                let videoSettings: [String: Any] = [
                    AVVideoCodecKey: AVVideoCodecType.hevc,
                    AVVideoWidthKey: conf.width,
                    AVVideoHeightKey: conf.height,
                    AVVideoCompressionPropertiesKey: [
                        AVVideoAverageBitRateKey: targetBitrate,
                        AVVideoExpectedSourceFrameRateKey: 60
                    ] as [String: Any]
                ]
                
                // for mic
                // Set up WAV-specific audio settings for microphone
                let micAudioSettings: [String: Any] = [
                    AVFormatIDKey: kAudioFormatLinearPCM,
                    AVSampleRateKey: 48000,
                    AVNumberOfChannelsKey: 2,
                    AVLinearPCMBitDepthKey: 16,
                    AVLinearPCMIsFloatKey: false,
                    AVLinearPCMIsBigEndianKey: false,
                    AVLinearPCMIsNonInterleaved: false
                ]
                
                recordMic = true  // Set to true if you want to enable microphone recording
                
                vwInput = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
                awInput = AVAssetWriterInput(mediaType: .audio, outputSettings: audioSettings)
                micWriterInput = AVAssetWriterInput(mediaType: .audio, outputSettings: micAudioSettings)
                
                vwInput.expectsMediaDataInRealTime = true
                awInput.expectsMediaDataInRealTime = true
                micWriterInput?.expectsMediaDataInRealTime = true
                
                if vW!.canAdd(vwInput) {
                    vW!.add(vwInput)
                }
                
                if vW!.canAdd(awInput) {
                    vW!.add(awInput)
                }
                
                if recordMic, let micWriterInput = micWriterInput, let micWriter = micWriter {
                    if micWriter.canAdd(micWriterInput) {
                        micWriter.add(micWriterInput)
                    }
                    
                    // Instead of tapping directly on the inputNode, we create a mixer node to amplify the mic signal.
                    let inputNode = audioEngine.inputNode
                    let inputFormat = inputNode.outputFormat(forBus: 0)
                    
                    // Create and attach a mixer node for the microphone.
                    let micMixer = AVAudioMixerNode()
                    audioEngine.attach(micMixer)
                    
                    // Connect the input node to the mic mixer.
                    audioEngine.connect(inputNode, to: micMixer, format: inputFormat)
                    
                    // Install a tap on the mixer node to boost the signal.
                    micMixer.installTap(onBus: 0, bufferSize: 1024, format: inputFormat) { [weak self] buffer, time in
                        guard let self = self,
                              let channelData = buffer.floatChannelData else { return }
                        
                        // Apply gain boost – adjust gainFactor as needed.
                        let gainFactor: Float = 4.0
                        let frameCount = Int(buffer.frameLength)
                        let channelCount = Int(buffer.format.channelCount)
                        
                        for channel in 0..<channelCount {
                            vDSP_vsmul(channelData[channel],
                                       1,
                                       [gainFactor],
                                       channelData[channel],
                                       1,
                                       vDSP_Length(frameCount))
                        }
                        
                        if let micWriterInput = self.micWriterInput,
                           micWriterInput.isReadyForMoreMediaData,
                           let sampleBuffer = buffer.asScreenRecorderWithSMicSampleBuffer {
                            micWriterInput.append(sampleBuffer)
                        }
                    }
                    
                    do {
                        try audioEngine.start()
                    } catch {
                        print("Error starting audio engine: \(error.localizedDescription)")
                    }
                    
                    // Start the mic writer separately
                    micWriter.startWriting()
                    micWriter.startSession(atSourceTime: CMTime.zero)
                }
                
                vW!.startWriting()
                    
            } catch {
                print("Error initializing video writer: \(error)")
                DispatchQueue.main.async {
                    self.state = .error(error)
                }
            }
        } else {
            print("Error: Downloads directory not found.")
            DispatchQueue.main.async {
                self.state = .error(NSError(domain: "ScreenRecorderError", code: 3,
                                        userInfo: ["message": "Downloads directory not found"]))
            }
        }
    }
    
    private func closeVideo() {
        guard let vW = vW else { return }
        
        let dispatchGroup = DispatchGroup()
        dispatchGroup.enter()
        
        vwInput.markAsFinished()
        awInput.markAsFinished()
        
        if recordMic, let micWriterInput = micWriterInput {
            micWriterInput.markAsFinished()
            audioEngine.inputNode.removeTap(onBus: 0)
            audioEngine.stop()
            
            if let micWriter = micWriter {
                dispatchGroup.enter()
                micWriter.finishWriting {
                    dispatchGroup.leave()
                }
            }
        }
        
        vW.finishWriting {
            dispatchGroup.leave()
        }
        
        dispatchGroup.wait()
    }
    
    // MARK: - SCStreamOutput Methods
    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of outputType: SCStreamOutputType) {
        guard sampleBuffer.isValid else { return }
        
        switch outputType {
        case .screen:
            guard let attachmentsArray = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: false) as? [[SCStreamFrameInfo: Any]],
                  let attachments = attachmentsArray.first else { return }
            guard let statusRawValue = attachments[SCStreamFrameInfo.status] as? Int,
                  let status = SCFrameStatus(rawValue: statusRawValue),
                  status == .complete else { return }
            
            if let vW = vW, vW.status == .writing {
                vW.startSession(atSourceTime: CMSampleBufferGetPresentationTimeStamp(sampleBuffer))
            }
            
            if vwInput.isReadyForMoreMediaData {
                vwInput.append(sampleBuffer)
            }
            
        case .audio:
            if awInput.isReadyForMoreMediaData {
                awInput.append(sampleBuffer)
            }
            
        default:
            assertionFailure("Unknown stream type")
        }
    }
    
    // MARK: - SCStreamDelegate Methods
    func stream(_ stream: SCStream, didStopWithError error: Error) {
        print("Stream stopped with error: \(error)")
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.stream = nil
            self.stopRecording()
            self.state = .error(error)
        }
    }
}

// MARK: - Buffer Extensions
extension AVAudioPCMBuffer {
    var asScreenRecorderWithSMicSampleBuffer: CMSampleBuffer? {
        let asbd = self.format.streamDescription
        var sampleBuffer: CMSampleBuffer? = nil
        var format: CMFormatDescription? = nil
        
        guard CMAudioFormatDescriptionCreate(
            allocator: kCFAllocatorDefault,
            asbd: asbd,
            layoutSize: 0,
            layout: nil,
            magicCookieSize: 0,
            magicCookie: nil,
            extensions: nil,
            formatDescriptionOut: &format
        ) == noErr else { return nil }
        
        var timing = CMSampleTimingInfo(
            duration: CMTime(value: 1, timescale: Int32(asbd.pointee.mSampleRate)),
            presentationTimeStamp: CMClockGetTime(CMClockGetHostTimeClock()),
            decodeTimeStamp: .invalid
        )
        
        guard CMSampleBufferCreate(
            allocator: kCFAllocatorDefault,
            dataBuffer: nil,
            dataReady: false,
            makeDataReadyCallback: nil,
            refcon: nil,
            formatDescription: format,
            sampleCount: CMItemCount(self.frameLength),
            sampleTimingEntryCount: 1,
            sampleTimingArray: &timing,
            sampleSizeEntryCount: 0,
            sampleSizeArray: nil,
            sampleBufferOut: &sampleBuffer
        ) == noErr else { return nil }
        
        guard CMSampleBufferSetDataBufferFromAudioBufferList(
            sampleBuffer!,
            blockBufferAllocator: kCFAllocatorDefault,
            blockBufferMemoryAllocator: kCFAllocatorDefault,
            flags: 0,
            bufferList: self.mutableAudioBufferList
        ) == noErr else { return nil }
        
        return sampleBuffer
    }
}
