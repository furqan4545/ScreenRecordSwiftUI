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
class ScreenRecorderWithHDR: NSObject, SCStreamDelegate, SCStreamOutput {
    
    // MARK: - Enums
    enum StreamType: Int {
        case screen, window, systemAudio
    }
    
    enum VideoQuality {
        case hd    // Standard HD recording
        case hdr   // High Dynamic Range recording
    }
    
    enum AudioQuality: Int {
        case normal = 128, good = 192, high = 256, extreme = 320
    }
    
    enum VideoFormat: String {
        case mov, mp4
    }
    
    enum RecordingType {
        case screen // Full screen recording
        case window(SCContentFilter) // Recording a specific window with a given filter
        case display(SCContentFilter) // Recording a specific display
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
    
    private var hasStartedSession = false
    private var videoQuality: VideoQuality = .hdr // Default to HDR
    
    // buffer queue
    private let sampleBufferQueue = DispatchQueue(label: "com.screenrecorder.sampleBufferQueue")
    
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
    
    // Initialize with specific video quality
    init(videoQuality: VideoQuality = .hdr) {
        self.videoQuality = videoQuality
        super.init()
        updateAudioSettings()
    }
    
    // MARK: - Public Methods
    func setVideoQuality(_ quality: VideoQuality) {
        self.videoQuality = quality
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
                    print("  - Width: \(display.width), Height: \(display.height)")
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
    
    func startRecording(type: RecordingType = .screen) {
        guard state != .recording else { return }
        
        state = .preparing
        
        switch type {
        case .screen:
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
            
        case .window(let windowFilter):
            streamType = .window
            filter = windowFilter
            
            Task {
                await record(filter: windowFilter)
            }
            
        case .display(let displayFilter):
            streamType = .screen // Or create a specific display type if needed
            filter = displayFilter
            
            Task {
                await record(filter: displayFilter)
            }
        
        }
    }
    
    func stopRecording() {
        guard state == .recording, let stream = stream else { return }
        
        stream.stopCapture()
        self.stream = nil
        closeVideo()
        
        // Reset the asset writers and session flag for the next recording.
        vW = nil
        micWriter = nil
        hasStartedSession = false
        
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
        //        let conf = SCStreamConfiguration()
        let conf: SCStreamConfiguration
        
        if videoQuality == .hdr {
            // For HDR, use the preset for HDR streaming
            conf = SCStreamConfiguration(preset: .captureHDRStreamCanonicalDisplay)
        } else {
            // For HD, use a standard configuration
            conf = SCStreamConfiguration()
        }
        
        conf.width = Int(filter.contentRect.width) * Int(filter.pointPixelScale)
        conf.height = Int(filter.contentRect.height) * Int(filter.pointPixelScale)
        conf.minimumFrameInterval = CMTime(value: 1, timescale: CMTimeScale(60))
        conf.showsCursor = true
        conf.capturesAudio = true
        
        ///  test
        conf.scalesToFit = true
        conf.queueDepth = 8
        /// test
        
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
            
            // Add HDR indicator to filename if recording in HDR
            let qualityTag = videoQuality == .hdr ? "-HDR" : ""
            let url = downloadsDirectory.appendingPathComponent("Recording\(qualityTag)-\(dateString).\(fileEnding)")
            //            let url = downloadsDirectory.appendingPathComponent("Recording-\(dateString).\(fileEnding)") // for main video
            let micUrl = downloadsDirectory.appendingPathComponent("Mic-Recording-\(dateString).wav") // for mic
            
            DispatchQueue.main.async {
                self.outputURL = url
                self.micOutputURL = micUrl
            }
            
            do {
                vW = try AVAssetWriter(outputURL: url, fileType: fileType!)
                
                // Microphone writer setup (WAV format)
                micWriter = try AVAssetWriter(outputURL: micUrl, fileType: .wav)
                
                // Configure video settings based on quality selection
                var videoSettings: [String: Any]
                
                if videoQuality == .hdr {
                    // HDR-specific settings (10-bit HEVC)
                    let fpsMultiplier: Double = Double(60) / 8
                    let encoderMultiplier: Double = 1.2 // Higher for HDR content
                    let targetBitrate = (Double(conf.width) * Double(conf.height) * fpsMultiplier * encoderMultiplier)
                    
                    let compressionProperties: [String: Any] = [
                        AVVideoAverageBitRateKey: targetBitrate,
                        AVVideoExpectedSourceFrameRateKey: 60,
                        AVVideoMaxKeyFrameIntervalKey: 60, // One keyframe per second
                        AVVideoProfileLevelKey: "HEVC_Main10_AutoLevel",
                        AVVideoColorPrimariesKey: AVVideoColorPrimaries_ITU_R_2020,
                        AVVideoTransferFunctionKey: AVVideoTransferFunction_ITU_R_2100_HLG, // or AVVideoTransferFunction_SMPTE_ST_2084_PQ
                        AVVideoYCbCrMatrixKey: AVVideoYCbCrMatrix_ITU_R_2020
                    ]
                    
                    videoSettings = [
                        AVVideoCodecKey: AVVideoCodecType.hevc,
                        AVVideoWidthKey: conf.width,
                        AVVideoHeightKey: conf.height,
                        AVVideoCompressionPropertiesKey: compressionProperties,
                        // Set the pixel format to 10-bit for HDR
                        AVVideoPixelAspectRatioKey: [
                            AVVideoPixelAspectRatioHorizontalSpacingKey: 1,
                            AVVideoPixelAspectRatioVerticalSpacingKey: 1
                        ]
                    ]
                } else {
                    // Standard HD settings (8-bit H.264)
                    let fpsMultiplier: Double = Double(60) / 8
                    let encoderMultiplier: Double = 0.9
                    let targetBitrate = (Double(conf.width) * Double(conf.height) * fpsMultiplier * encoderMultiplier)
                    
                    videoSettings = [
                        AVVideoCodecKey: AVVideoCodecType.hevc, // Still using HEVC but with standard settings
                        AVVideoWidthKey: conf.width,
                        AVVideoHeightKey: conf.height,
                        AVVideoCompressionPropertiesKey: [
                            AVVideoAverageBitRateKey: targetBitrate,
                            AVVideoExpectedSourceFrameRateKey: 60
                        ] as [String: Any],
                        AVVideoPixelAspectRatioKey: [
                            AVVideoPixelAspectRatioHorizontalSpacingKey: 1,
                            AVVideoPixelAspectRatioVerticalSpacingKey: 1
                        ]
                    ]
                }
                
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
                
                // For HDR, make sure we handle any properties in the source
                if videoQuality == .hdr {
                    vwInput.performsMultiPassEncodingIfSupported = true
                    
                    // Instead, you can use these relevant properties for HDR:
                    vwInput.mediaTimeScale = 60 // Set time scale for precision
                    
                    // For HDR content, we might want to ensure highest quality encoding
                    if #available(macOS 10.15, *) {
                        vwInput.preferredMediaChunkAlignment = 512 * 1024 // 512KB chunks for optimization
                        vwInput.preferredMediaChunkDuration = CMTime(value: 1, timescale: 2) // 0.5 second chunks
                    }
                }
                
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
                           let sampleBuffer = buffer.asScreenRecorderWithHDRSampleBuffer {
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
        
        // Process sample buffer on a serial queue to avoid race conditions
        sampleBufferQueue.async { [weak self] in
            guard let self = self else { return }
            
            switch outputType {
            case .screen:
                guard let attachmentsArray = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer,
                                                                                     createIfNecessary: false) as? [[SCStreamFrameInfo: Any]],
                      let attachments = attachmentsArray.first else { return }
                guard let statusRawValue = attachments[SCStreamFrameInfo.status] as? Int,
                      let status = SCFrameStatus(rawValue: statusRawValue),
                      status == .complete else { return }
                
                // HDR metadata logging (no change needed)
                if self.videoQuality == .hdr {
                    if let formatDescription = CMSampleBufferGetFormatDescription(sampleBuffer) {
                        if !self.hasStartedSession {
                            // Get video format extension dictionary with color information
                            let extensionDictionary = CMFormatDescriptionGetExtensions(formatDescription) as Dictionary?
                            let videoDict = extensionDictionary?[kCMFormatDescriptionExtension_FormatName] as? String
                            
                            // Access the color space extensions
                            if let colorAttachments = CMFormatDescriptionGetExtension(
                                formatDescription,
                                extensionKey: kCMFormatDescriptionExtension_ColorPrimaries
                            ) {
                                print("Recording with color primaries: \(colorAttachments)")
                            }
                            
                            if let transferFunction = CMFormatDescriptionGetExtension(
                                formatDescription,
                                extensionKey: kCMFormatDescriptionExtension_TransferFunction
                            ) {
                                print("Recording with transfer function: \(transferFunction)")
                            }
                            
                            // More basic approach, just print the format name
                            print("Recording with format: \(videoDict ?? "Unknown")")
                        }
                    }
                }
                
                // Start the session only once at the first valid frame
                if !self.hasStartedSession {
                    if let vW = self.vW, vW.status == .writing {
                        let timestamp = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
                        vW.startSession(atSourceTime: timestamp)
                        self.hasStartedSession = true
                        print("Started AVAssetWriter session at \(timestamp)")
                        
                        // Append the first frame after starting the session
                        if self.vwInput.isReadyForMoreMediaData {
                            self.vwInput.append(sampleBuffer)
                        }
                    }
                } else {
                    // Only append if session is already started
                    if self.vwInput.isReadyForMoreMediaData {
                        self.vwInput.append(sampleBuffer)
                    }
                }
                
            case .audio:
                // Only append audio after session has started
                if self.hasStartedSession && self.awInput.isReadyForMoreMediaData {
                    self.awInput.append(sampleBuffer)
                }
                
            default:
                assertionFailure("Unknown stream type")
            }
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
    var asScreenRecorderWithHDRSampleBuffer: CMSampleBuffer? {
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
