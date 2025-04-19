
//
//  ScreenRecordWithSepMic.swift
//  ScreenRecord
//
//  Created by Furqan Ali on 3/25/25.
//  Modified by AI on [20, April 2025] - Reverted Screen Recording logic to original, separated Mic logic.
//

import Foundation
import AVFoundation
import ScreenCaptureKit
import Combine
// Removed Accelerate and CoreAudio imports
import AppKit // For NSWorkspace

/// Model class that handles screen recording functionality
class ScreenRecorderWithHDR: NSObject, SCStreamDelegate, SCStreamOutput {

    // MARK: - Enums
    // --- START: Keep Enums EXACTLY as in Original ---
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
        case area(SCDisplay, CGRect)
    }

    enum RecorderState: Equatable {
        case idle
        case preparing
        case recording
        case saving
        case error(Error)

        static func == (lhs: RecorderState, rhs: RecorderState) -> Bool {
            switch (lhs, rhs) {
            case (.idle, .idle),
                (.preparing, .preparing),
                (.recording, .recording),
                (.saving, .saving):
                return true
            case (.error(let lhsError), .error(let rhsError)):
                return lhsError.localizedDescription == rhsError.localizedDescription // Original comparison
            default:
                return false
            }
        }
    }
    // --- END: Keep Enums EXACTLY as in Original ---

    // MARK: - Properties
    // --- START: Keep Properties related to Screen/System Audio/State EXACTLY as in Original ---
    private var availableContent: SCShareableContent?
    private var filter: SCContentFilter?
    private var screen: SCDisplay?
    private var audioSettings: [String: Any]!
    private var stream: SCStream?
    private var streamType: StreamType?
    private var vW: AVAssetWriter?
    private var vwInput, awInput: AVAssetWriterInput! // REMOVED: micInput
    // REMOVED: private let audioEngine = AVAudioEngine()

    private var hasStartedSession = false
    private var videoQuality: VideoQuality = .hdr // Default to HDR

    var recordedVideoWidth: Int = 1920
    var recordedVideoHeight: Int = 1080

    // microphone properties (Keep flag, remove direct device ref)
    private var isMicrophoneEnabled: Bool = true
    // REMOVED: private var selectedMicrophone: AVCaptureDevice?

    // buffer queue (Keep EXACTLY as original)
    private let sampleBufferQueue = DispatchQueue(label: "com.screenrecorder.sampleBufferQueue")

    // REMOVED: Microphone writer properties
    // REMOVED: private var micWriter: AVAssetWriter?
    // REMOVED: private var micWriterInput: AVAssetWriterInput?
    // REMOVED: private var recordMic = false // Use isMicrophoneEnabled instead

    // System Audio (Keep EXACTLY as original)
    private var isSystemAudioEnabled: Bool = true

    // State Flags (Keep EXACTLY as original)
    private var isStoppingRecording = false
    // --- END: Keep Properties related to Screen/System Audio/State EXACTLY as in Original ---

    // Microphone Recorder Instance (ADDED for separation)
    private let microphoneRecorder = MicrophoneRecorder()
    private var micOutputURLSubscription: AnyCancellable? // Store subscription (ADDED for separation)


    // MARK: - Published Properties (Keep EXACTLY as in Original)
    @Published var state: RecorderState = .idle
    @Published var displays: [SCDisplay] = []
    @Published var outputURL: URL?
    @Published var micOutputURL: URL? // Keep for observing mic recorder

    // MARK: - Initialization (Keep EXACTLY as in Original, add mic observation)
    override init() {
        super.init()
        updateAudioSettings()
        // Observe the microphone recorder's output URL (ADDED for separation)
        observeMicOutputURL()
    }

    // Initialize with specific video quality (Keep EXACTLY as in Original, add mic observation)
    init(videoQuality: VideoQuality = .hdr) {
        self.videoQuality = videoQuality
        super.init()
        updateAudioSettings()
        // Observe the microphone recorder's output URL (ADDED for separation)
        observeMicOutputURL()
    }
    
    // Helper for mic observation (ADDED for separation)
    private func observeMicOutputURL() {
        micOutputURLSubscription = microphoneRecorder.$outputURL
            .receive(on: DispatchQueue.main)
            .sink { [weak self] url in
                self?.micOutputURL = url
            }
    }

    // MARK: - Public Methods
    // --- START: Keep Screen/System Audio Config Methods EXACTLY as in Original ---
    func setVideoQuality(_ quality: VideoQuality) {
        self.videoQuality = quality
    }

    func setSystemAudioEnabled(_ enabled: Bool) {
        isSystemAudioEnabled = enabled
        print("System audio recording \(enabled ? "enabled" : "disabled")")
    }

    var selectedFilter: SCContentFilter? {
        return filter
    }
    // --- END: Keep Screen/System Audio Config Methods EXACTLY as in Original ---

    // Method to enable/disable microphone recording (MODIFIED: Keep flag, remove direct action)
    func setMicrophoneEnabled(_ enabled: Bool) {
        isMicrophoneEnabled = enabled
        print("Microphone recording \(enabled ? "enabled" : "disabled")")
    }

    // Method delegates microphone selection (MODIFIED: Delegate, remove internal logic)
    func selectMicrophone(_ microphone: AVCaptureDevice) {
        // REMOVED: selectedMicrophone = microphone
        print("Selected microphone: \(microphone.localizedName)") // Keep log from original if desired
        // REMOVED: setMicrophoneAsDefault(captureDevice: microphone)
        microphoneRecorder.selectMicrophone(microphone) // Delegate to new class
    }

    // REMOVED: private func setMicrophoneAsDefault(captureDevice: AVCaptureDevice) - Now internal to MicrophoneRecorder


    // MARK: - Public Methods: Permissions (Keep Screen Perm EXACTLY as original, Delegate Mic Perm)
    func requestPermission() { // Renamed from original requestScreenRecordingPermission for clarity, logic is identical
        SCShareableContent.getExcludingDesktopWindows(true, onScreenWindowsOnly: true) { [weak self] content, error in
            guard let self = self else { return }

            // Keep original logic EXACTLY
            DispatchQueue.main.async {
                if let error = error {
                    // Original error handling logic
                    if let scError = error as? SCStreamError, scError.code == .userDeclined {
                         print("User declined screen recording permission")
                         if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
                              NSWorkspace.shared.open(url)
                         }
                    // Use default case for other errors as in original
                    } else {
                        print("[Err] Failed to fetch available content: \(error.localizedDescription)")
                        self.state = .error(error) // Set error state as in original
                    }
                    return // Return as in original
                }

                self.availableContent = content
                self.displays = content?.displays ?? []

                // Original debug info logic
                for (i, display) in self.displays.enumerated() {
                    let isMain = display.displayID == CGMainDisplayID()
                    let displayName = "Display \(i+1)\(isMain ? " (Main)" : "")"
                    print(displayName)
                    print("  - Width: \(display.width), Height: \(display.height)")
                }

                self.state = .idle // Set idle state as in original
            }
        }
    }

    // Delegates microphone permission request (MODIFIED: Delegate)
    func requestMicrophonePermission(completion: @escaping (Bool) -> Void) {
        // Original implementation removed, delegate instead
        microphoneRecorder.requestPermission(completion: completion)
    }

    // MARK: - Recording Control (Keep EXACTLY as in original, add mic start/stop calls)

    func startRecording(type: RecordingType = .screen) {
        // Keep guards and state changes EXACTLY as in original
        guard state != .recording else { return }
        state = .preparing

        // Keep filter setup logic EXACTLY as in original
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
                // Keep Task logic EXACTLY as in original
                Task {
                    if let filter = filter {
                        await record(filter: filter)
                    } else {
                         // Keep state update EXACTLY as in original
                        await MainActor.run { // Ensure UI update is on main
                            state = .error(NSError(domain: "ScreenRecorderError", code: 1, userInfo: ["message": "Failed to create content filter"]))
                        }
                    }
                }
            } else {
                 // Keep state update EXACTLY as in original
                 DispatchQueue.main.async { // Ensure UI update is on main
                     self.state = .error(NSError(domain: "ScreenRecorderError", code: 2, userInfo: ["message": "No display available"]))
                 }
            }

        case .window(let windowFilter):
            streamType = .window
            filter = windowFilter
            // Keep Task logic EXACTLY as in original
            Task { await record(filter: windowFilter) }

        case .display(let displayFilter):
            streamType = .screen
            filter = displayFilter
            // Keep Task logic EXACTLY as in original
            Task { await record(filter: displayFilter) }

        case .area(let targetDisplay, let areaRect):
            streamType = .screen
            // Keep filter setup EXACTLY as in original
            let excludedApps = availableContent?.applications.filter {
                Bundle.main.bundleIdentifier == $0.bundleIdentifier
            } ?? []
            filter = SCContentFilter(display: targetDisplay,
                                     excludingApplications: excludedApps,
                                     exceptingWindows: [])
            // Keep Task logic EXACTLY as in original
            Task {
                if let filter = filter {
                    await record(filter: filter, isAreaRecording: true, areaRect: areaRect)
                } else {
                     // Keep state update EXACTLY as in original
                    await MainActor.run { // Ensure UI update is on main
                        state = .error(NSError(domain: "ScreenRecorderError", code: 1, userInfo: ["message": "Failed to create content filter"]))
                    }
                }
            }
        }
    }


    func stopRecording() {
        // Keep guard and stream access EXACTLY as in original
        guard state == .recording, let stream = stream else { return }

        // Keep state change EXACTLY as in original
        state = .saving

        // Keep flag set EXACTLY as in original
        isStoppingRecording = true

        // --- ADDED: Stop microphone recorder ---
        if isMicrophoneEnabled {
            print("ScreenRecorder: Stopping microphone recorder.")
            microphoneRecorder.stopRecording()
        }
        // --- End ADDED ---


        // Keep timeout logic EXACTLY as in original
        let timeoutWorkItem = DispatchWorkItem {
            print("Recording stop timeout triggered - forcing completion")
            // Call original completion method
            self.completeRecordingStop()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 5.0, execute: timeoutWorkItem)

        // Keep stream stop capture EXACTLY as in original
        stream.stopCapture()

        // // Give a small delay for last frames to process
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            guard let self = self else { return }
            // Cancel timeout since we're executing normally
            timeoutWorkItem.cancel()
            // // Complete the recording stop process
            self.completeRecordingStop()
        }
    }

    // Keep completeRecordingStop EXACTLY as in original (it calls closeVideo)
    // except remove micWriter = nil reset
    // Add this method to handle the actual cleanup
    private func completeRecordingStop() {
        // Set stream to nil as in original
        self.stream = nil

        // Close video files as in original (this will call the modified closeVideo)
        closeVideo()

        // Ensure the saving state lasts at least 0.5 second for visual feedback
        let savingStartTime = Date()
        let minimumSavingDuration: TimeInterval = 0.5 // Use original value

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in // Use original delay
            guard let self = self else { return }

            let elapsedTime = Date().timeIntervalSince(savingStartTime)
            let remainingTime = max(0, minimumSavingDuration - elapsedTime)

            DispatchQueue.main.asyncAfter(deadline: .now() + remainingTime) { [weak self] in
                guard let self = self else { return }

                // Reset state as in original, but WITHOUT micWriter
                vW = nil
                // REMOVED: micWriter = nil
                vwInput = nil // Ensure these are reset here too
                awInput = nil
                hasStartedSession = false
                streamType = nil
                isStoppingRecording = false
                state = .idle
                filter = nil // Also reset filter/screen if desired, original didn't explicitly do it here
                screen = nil
                print("ScreenRecorder: State reset after stop.") // Added log for clarity
            }
        }
    }


    // MARK: - Private Methods
    // Keep updateAudioSettings EXACTLY as in original
    private func updateAudioSettings() {
        audioSettings = [AVSampleRateKey: 48000, AVNumberOfChannelsKey: 2]
        audioSettings[AVFormatIDKey] = kAudioFormatMPEG4AAC
        audioSettings[AVEncoderBitRateKey] = AudioQuality.high.rawValue * 1000
    }

    // Keep record signature and async EXACTLY as in original
    private func record(filter: SCContentFilter, isAreaRecording: Bool = false, areaRect: CGRect? = nil) async {
        // Keep SCStreamConfiguration setup EXACTLY as in original
        let conf: SCStreamConfiguration
        if videoQuality == .hdr {
            conf = SCStreamConfiguration(preset: .captureHDRStreamCanonicalDisplay)
        } else {
            conf = SCStreamConfiguration()
        }

        // Keep dimension/scaling logic EXACTLY as in original
        let scale = CGFloat(filter.pointPixelScale) // Use original CGFloat cast
        conf.width = Int(filter.contentRect.width * scale)
        conf.height = Int(filter.contentRect.height * scale)
        conf.minimumFrameInterval = CMTime(value: 1, timescale: CMTimeScale(60))

        recordedVideoWidth = conf.width
        recordedVideoHeight = conf.height

        // Keep area recording override logic EXACTLY as in original
        if isAreaRecording, let areaRect = areaRect {
            conf.width = Int(areaRect.width * scale)
            conf.height = Int(areaRect.height * scale)
            recordedVideoWidth = conf.width
            recordedVideoHeight = conf.height
            conf.sourceRect = areaRect
            //  conf.backgroundColor = .white  /// (optional) for modifying background color
        }

        // Keep other conf properties EXACTLY as in original
        conf.showsCursor = true
        conf.capturesAudio = isSystemAudioEnabled
        conf.scalesToFit = true
        conf.queueDepth = 6

        // Keep audio conf properties EXACTLY as in original (only set if audio enabled)
         if isSystemAudioEnabled {
            conf.sampleRate = audioSettings[AVSampleRateKey] as! Int
            conf.channelCount = audioSettings[AVNumberOfChannelsKey] as! Int
         }


        // Keep stream initialization EXACTLY as in original
        stream = SCStream(filter: filter, configuration: conf, delegate: self)

        // Keep do-catch block structure EXACTLY as in original
        do {
            if let stream = stream {
                // Keep addStreamOutput calls EXACTLY as in original (using .global() queue)
                try stream.addStreamOutput(self, type: .screen, sampleHandlerQueue: .global())
                if isSystemAudioEnabled {
                    try stream.addStreamOutput(self, type: .audio, sampleHandlerQueue: .global())
                }

                // Call the modified initVideoWriters (based on original initVideo but without mic parts)
                 try initVideoWriters(conf: conf) // Use helper

                // Keep startCapture and state update EXACTLY as in original
                try await stream.startCapture()
                await MainActor.run {
                    self.state = .recording
                }
            }
        } catch {
            // Keep error handling EXACTLY as in original
            await MainActor.run {
                self.state = .error(error)
            }
            // REMOVED: return (original didn't explicitly return here, relied on state change)
             // Clean up partially started writers on error
              self.vW = nil // Nil out writer
              self.microphoneRecorder.stopRecording() // Ensure mic stops if started
              print("ScreenRecorder: Cleanup after record error.")
        }
    }

    // Renamed from original initVideo, but logic for screen/system audio is IDENTICAL
    // Microphone logic is REMOVED and replaced with delegate call
    private func initVideoWriters(conf: SCStreamConfiguration) throws {
        let fileEnding = VideoFormat.mp4.rawValue
        let fileType: AVFileType = .mp4 // Use direct assignment as original did

        // Keep file URL generation EXACTLY as in original
        guard let downloadsDirectory = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first else {
             // Throw error like original would implicitly do by crashing later, but safer to throw
             throw NSError(domain: "ScreenRecorderError", code: 3, userInfo: [NSLocalizedDescriptionKey: "Downloads directory not found"])
        }

        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd-HH-mm-ss"
        let dateString = dateFormatter.string(from: Date())
        let qualityTag = videoQuality == .hdr ? "-HDR" : ""
        let url = downloadsDirectory.appendingPathComponent("Recording\(qualityTag)-\(dateString).\(fileEnding)")
        let micUrl = downloadsDirectory.appendingPathComponent("Mic-Recording-\(dateString).wav") // Keep micUrl generation

        // Keep URL publishing EXACTLY as in original
        DispatchQueue.main.async {
            self.outputURL = url
            self.micOutputURL = micUrl // Keep this for initial UI update if needed
        }

        // Keep AVAssetWriter creation EXACTLY as in original
        vW = try AVAssetWriter(outputURL: url, fileType: fileType)

        // Keep video settings logic EXACTLY as in original
        var videoSettings: [String: Any]
        if videoQuality == .hdr {
            let fpsMultiplier: Double = Double(60) / 8
            let encoderMultiplier: Double = 1.2  // Higher for HDR content
            let targetBitrate = (Double(conf.width) * Double(conf.height) * fpsMultiplier * encoderMultiplier)
            let compressionProperties: [String: Any] = [
                AVVideoAverageBitRateKey: targetBitrate,
                AVVideoExpectedSourceFrameRateKey: 60,
                AVVideoMaxKeyFrameIntervalKey: 60,
                AVVideoProfileLevelKey: "HEVC_Main10_AutoLevel", // Use original string
                AVVideoColorPrimariesKey: AVVideoColorPrimaries_ITU_R_2020,
                AVVideoTransferFunctionKey: AVVideoTransferFunction_ITU_R_2100_HLG,
                AVVideoYCbCrMatrixKey: AVVideoYCbCrMatrix_ITU_R_2020
            ]
            videoSettings = [
                AVVideoCodecKey: AVVideoCodecType.hevc,
                AVVideoWidthKey: conf.width,
                AVVideoHeightKey: conf.height,
                AVVideoCompressionPropertiesKey: compressionProperties,
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
                AVVideoCodecKey: AVVideoCodecType.hevc,
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

        // REMOVED: Mic audio settings setup

        // REMOVED: recordMic = isMicrophoneEnabled

        // Keep AVAssetWriterInput creation for video/audio EXACTLY as in original
        vwInput = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
        awInput = AVAssetWriterInput(mediaType: .audio, outputSettings: audioSettings)
        // REMOVED: micWriterInput = AVAssetWriterInput(...)

        vwInput.expectsMediaDataInRealTime = true
        awInput.expectsMediaDataInRealTime = true
        // REMOVED: micWriterInput?.expectsMediaDataInRealTime = true

        // Keep HDR input settings configuration EXACTLY as in original
        if videoQuality == .hdr {
            vwInput.performsMultiPassEncodingIfSupported = true
            vwInput.mediaTimeScale = 600 // Using a higher timescale like 600 allows the AVAssetWriter to represent the exact presentation time of each frame more accurately than if you used a lower value like 60 (which would only give you precision down to 1/60th of a second). This helps avoid potential rounding errors and ensures smoother playback, especially with variable frame rates or high frame rates.
            vwInput.preferredMediaChunkAlignment = 512 * 1024
            vwInput.preferredMediaChunkDuration = CMTime(value: 1, timescale: 2)
        }

        // Keep adding inputs to vW EXACTLY as in original
        guard let vW = vW else { // Add guard for safety, original implicitly unwrapped
             throw NSError(domain: "ScreenRecorderError", code: 6, userInfo: [NSLocalizedDescriptionKey: "AVAssetWriter is nil after initialization attempt"])
        }
        if vW.canAdd(vwInput) {
            vW.add(vwInput)
        } else {
            throw NSError(domain: "ScreenRecorderError", code: 7, userInfo: [NSLocalizedDescriptionKey: "Cannot add video input to writer"])
        }

        // Only add audio if enabled, as in original implicitly (conf.capturesAudio controlled adding stream output)
        // Explicitly check here when adding input for robustness, mirroring original intent.
        if isSystemAudioEnabled {
             if vW.canAdd(awInput) {
                 vW.add(awInput)
             } else {
                 print("Warning: Could not add system audio input to writer.")
                 // Allow proceeding without system audio if adding fails, or throw error
                  // throw NSError(domain: "ScreenRecorderError", code: 8, userInfo: [NSLocalizedDescriptionKey: "Cannot add system audio input to writer"])
             }
        }


        // REMOVED: All mic writer input adding, audio engine setup, tap installation, engine start, mic writer start

        // Keep vW startWriting EXACTLY as in original
         if !vW.startWriting() { // Check return value
             if let error = vW.error { throw error }
             else { throw NSError(domain: "ScreenRecorderError", code: 9, userInfo: [NSLocalizedDescriptionKey: "AVAssetWriter failed to start writing."]) }
         }
         print("ScreenRecorder: Main AVAssetWriter started writing.") // Add log


        // --- ADDED: Start Microphone Recorder ---
        if isMicrophoneEnabled {
            print("ScreenRecorder: Starting microphone recorder with URL: \(micUrl.path)")
            microphoneRecorder.startRecording(outputURL: micUrl) // Start the separate recorder
            // Note: Mic recorder's output URL will update via Combine subscription
        }
        // --- End ADDED ---

    }


    // Modify closeVideo to match original logic for screen/audio, remove mic parts
    private func closeVideo() {
        guard let vW = vW else { return }

        // Keep DispatchGroup logic EXACTLY as in original
        let dispatchGroup = DispatchGroup()

        // Mark screen/audio inputs finished if they exist (original assumed they did)
        dispatchGroup.enter() // Use group like original timeout version did implicitly
        if let vwInput = vwInput { vwInput.markAsFinished() }
        if let awInput = awInput { awInput.markAsFinished() } // Should only mark if it was added
        dispatchGroup.leave()


        // REMOVED: Microphone finalization logic (micWriterInput.markAsFinished, audioEngine stop/tap, micWriter.finishWriting)


        // Keep vW finalization logic EXACTLY as in original timeout version
        dispatchGroup.enter()
        vW.finishWriting {
             print("ScreenRecorder: Main writer finished writing. Status: \(vW.status.rawValue)") // Log added
             if let error = vW.error { print("ScreenRecorder: Main writer finished with error: \(error)") }
            dispatchGroup.leave()
        }

        // Keep timeout logic EXACTLY as in original timeout version
        let result = dispatchGroup.wait(timeout: .now() + 3.0)
        if result == .timedOut {
            print("Warning: Video finalization timed out")
        }
    }


    // MARK: - SCStreamOutput Methods
    // Keep stream output method signature EXACTLY as in original
    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of outputType: SCStreamOutputType) {
        // Keep outer guards EXACTLY as in original
        guard sampleBuffer.isValid, !isStoppingRecording else { return }

        // Keep sampleBufferQueue.async block EXACTLY as in original
        sampleBufferQueue.async { [weak self] in
            guard let self = self, !self.isStoppingRecording else { return }

            // Keep writer status check (original implicitly checked inside)
             guard let vW = self.vW, vW.status == .writing else { return }

            // Keep switch statement structure EXACTLY as in original
            switch outputType {
            case .screen:
                // Keep attachment/status check EXACTLY as in original
                guard let attachmentsArray = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: false) as? [[SCStreamFrameInfo: Any]],
                      let attachments = attachmentsArray.first else { return }
                guard let statusRawValue = attachments[SCStreamFrameInfo.status] as? Int,
                      let status = SCFrameStatus(rawValue: statusRawValue),
                      status == .complete else { return }

                // Keep HDR metadata logging EXACTLY as in original (omitted here for brevity)
                // if self.videoQuality == .hdr { ... }

                // Keep hasStartedSession logic EXACTLY as in original
                if !self.hasStartedSession {
                    // Original check used optional chaining, replicate that
                    if let vW = self.vW, vW.status == .writing { // Redundant check inside queue? Keep as original.
                        let timestamp = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
                        guard timestamp.isValid else { return } // Add check for valid timestamp
                        vW.startSession(atSourceTime: timestamp)
                        self.hasStartedSession = true
                        print("Started AVAssetWriter session at \(timestamp.seconds)") // Use seconds for clarity

                        // Keep append logic EXACTLY as in original
                        if self.vwInput?.isReadyForMoreMediaData ?? false { // Use optional chaining like original might implicitly
                            self.vwInput.append(sampleBuffer)
                        }
                    }
                } else {
                    // Keep append logic EXACTLY as in original
                    if self.vwInput?.isReadyForMoreMediaData ?? false { // Use optional chaining
                        self.vwInput.append(sampleBuffer)
                    } else {
                        // Log dropped frame if desired
                        // print("ScreenRecorder: Dropped video frame - input not ready.")
                    }
                }

            case .audio:
                // Keep append logic EXACTLY as in original
                if self.hasStartedSession && (self.awInput?.isReadyForMoreMediaData ?? false) { // Use optional chaining
                    self.awInput.append(sampleBuffer)
                } else if self.hasStartedSession {
                    // Log dropped frame if desired
                    // print("ScreenRecorder: Dropped audio frame - input not ready.")
                }

            default:
                 // Keep assertionFailure EXACTLY as in original
                assertionFailure("Unknown stream type")
            }
        }
    }

    // MARK: - SCStreamDelegate Methods
    // Keep stream delegate method signature and logic EXACTLY as in original
    func stream(_ stream: SCStream, didStopWithError error: Error) {
        print("Stream stopped with error: \(error)")
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }

            // --- ADDED: Ensure microphone recorder is stopped on stream error ---
             self.microphoneRecorder.stopRecording() // Stop mic recorder too
            // --- End ADDED ---

            // Keep original state update and stopRecording call EXACTLY
            self.stream = nil // Original did this before calling stopRecording
            self.stopRecording() // Call original stopRecording logic
            self.state = .error(error) // Set state as in original
        }
    }
}

// REMOVED: AVAudioPCMBuffer extension (Now in MicrophoneRecorder.swift)
