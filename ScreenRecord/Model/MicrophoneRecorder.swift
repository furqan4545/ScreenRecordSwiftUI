//
//  MicrophoneRecorder.swift
//  ScreenRecord
//
//  Created by Furqan Ali on 4/19/25.
//


import Foundation
import AVFoundation
import Accelerate
import CoreAudio
import Combine // Added for @Published

class MicrophoneRecorder: NSObject {

    // MARK: - Properties
    private let audioEngine = AVAudioEngine()
    private var selectedMicrophone: AVCaptureDevice?
    private var micWriter: AVAssetWriter?
    private var micWriterInput: AVAssetWriterInput?
    private var isRecording = false

    // Buffer queue (can be shared or specific, using a specific one here)
    // Note: The original code used a global queue for the tap, which might have concurrency issues.
    // Keeping the tap logic as close as possible to original for now.
    // Consider if a dedicated serial queue is better for the tap block in a real app.

    // MARK: - Published Properties
    @Published var outputURL: URL?

    // MARK: - Initialization
    override init() {
        super.init()
        // Potential setup if needed in the future
    }

    // MARK: - Public Methods

    func requestPermission(completion: @escaping (Bool) -> Void) {
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

    func selectMicrophone(_ microphone: AVCaptureDevice) {
        selectedMicrophone = microphone
        print("Selected microphone: \(microphone.localizedName)")

        // Set this device as the default input (Moved from ScreenRecorder)
        setMicrophoneAsDefault(captureDevice: microphone)
    }

    func startRecording(outputURL: URL) {
        guard !isRecording else {
            print("MicrophoneRecorder: Already recording.")
            return
        }
        
        print("MicrophoneRecorder: Starting recording to \(outputURL.path)")
        self.outputURL = outputURL // Store the URL

        do {
            // Microphone writer setup (WAV format)
            micWriter = try AVAssetWriter(outputURL: outputURL, fileType: .wav)

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

            micWriterInput = AVAssetWriterInput(mediaType: .audio, outputSettings: micAudioSettings)
            micWriterInput?.expectsMediaDataInRealTime = true

            guard let micWriterInput = micWriterInput, let micWriter = micWriter else {
                throw NSError(domain: "MicrophoneRecorderError", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to initialize writer or input"])
            }

            if micWriter.canAdd(micWriterInput) {
                micWriter.add(micWriterInput)
            } else {
                 throw NSError(domain: "MicrophoneRecorderError", code: 2, userInfo: [NSLocalizedDescriptionKey: "Cannot add input to mic writer"])
            }

            // Reset the audio engine if it was running
            if audioEngine.isRunning {
                audioEngine.stop()
            }
            audioEngine.reset()

            // Instead of tapping directly on the inputNode, we create a mixer node to amplify the mic signal.
            let inputNode = audioEngine.inputNode
            let inputFormat = inputNode.outputFormat(forBus: 0)

            // Log the selected microphone for debugging
            if let selectedMic = selectedMicrophone {
                print("MicrophoneRecorder: Attempting to use microphone: \(selectedMic.localizedName)")
                // Note: On macOS, the system handles the default input device
                // The user needs to select their preferred device in System Preferences/Settings
            }

            // Create and attach a mixer node for the microphone.
            let micMixer = AVAudioMixerNode()
            audioEngine.attach(micMixer)

            // Connect the input node to the mic mixer.
            audioEngine.connect(inputNode, to: micMixer, format: inputFormat)

            // Install a tap on the mixer node to boost the signal.
            micMixer.installTap(onBus: 0, bufferSize: 1024, format: inputFormat) { [weak self] buffer, time in
                guard let self = self, self.isRecording, // Ensure still recording
                      let micWriterInput = self.micWriterInput,
                      micWriterInput.isReadyForMoreMediaData,
                      let channelData = buffer.floatChannelData else { return }

                // Apply gain boost – adjust gainFactor as needed.
                let gainFactor: Float = 4.0 // Keep original gain factor
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

                // Use the existing extension method to convert buffer
                if let sampleBuffer = buffer.asScreenRecorderWithHDRSampleBuffer {
                     // Append on the same queue the tap is called on, as original
                     micWriterInput.append(sampleBuffer)
                } else {
                    print("MicrophoneRecorder: Failed to convert buffer to sample buffer")
                }
            }

            // Start the audio engine
            try audioEngine.start()

            // Start the mic writer separately
            if micWriter.startWriting() {
                 micWriter.startSession(atSourceTime: CMTime.zero)
                 isRecording = true
                 print("MicrophoneRecorder: Started writing session.")
            } else {
                isRecording = false // Failed to start
                if let error = micWriter.error {
                    throw error // Propagate the writer error
                } else {
                    throw NSError(domain: "MicrophoneRecorderError", code: 4, userInfo: [NSLocalizedDescriptionKey: "Mic writer failed to start writing without specific error."])
                }
            }

        } catch {
            print("MicrophoneRecorder: Error starting recording: \(error)")
            // Clean up partially initialized state
            stopRecordingInternal(isError: true) // Use internal stop to avoid duplicate prints
            // Optionally rethrow or handle error state
        }
    }

    func stopRecording() {
        stopRecordingInternal(isError: false)
    }

    // MARK: - Private Methods

    private func stopRecordingInternal(isError: Bool) {
        guard isRecording || isError else { // Allow cleanup even if not fully recording in case of error
             if !isError { print("MicrophoneRecorder: Not recording.") }
            return
        }
        if !isError { print("MicrophoneRecorder: Stopping recording.") }
        
        isRecording = false // Set immediately to prevent tap block from appending more

        // Use a dispatch group to wait for writer finalization, similar to original
        let dispatchGroup = DispatchGroup()

        // Remove tap and stop engine first
        if audioEngine.isRunning {
             audioEngine.inputNode.removeTap(onBus: 0)
             audioEngine.stop()
             print("MicrophoneRecorder: Audio engine stopped and tap removed.")
        }

        if let micWriterInput = micWriterInput, micWriter?.status == .writing {
            // Check if input is already marked finished to avoid crash
            // Note: This check might not be strictly necessary if logic flow is correct,
            // but adds safety. Original code didn't have this check.
             var isAlreadyFinished = false
             if #available(macOS 11.0, *) { // Check availability for status property if needed
                 // isAlreadyFinished = micWriterInput.status == .finished // status property not directly available
             }
             // Simpler check: Assume not finished unless explicitly tracked.
             // If stopRecording is called multiple times, markAsFinished would crash.
             // The `isRecording` flag should prevent multiple calls.

             micWriterInput.markAsFinished()
             print("MicrophoneRecorder: Mic writer input marked as finished.")
        } else {
            print("MicrophoneRecorder: Mic writer input not available or writer not writing.")
        }

        if let micWriter = micWriter, micWriter.status == .writing {
            dispatchGroup.enter()
            micWriter.finishWriting { [weak self] in
                print("MicrophoneRecorder: Mic writer finished writing. Status: \(micWriter.status.rawValue)")
                if let error = micWriter.error {
                    print("MicrophoneRecorder: Mic writer finished with error: \(error)")
                }
                // Reset writer and input *after* completion handler
                self?.micWriter = nil
                self?.micWriterInput = nil
                dispatchGroup.leave()
            }
        } else {
             if let micWriter = micWriter {
                  print("MicrophoneRecorder: Mic writer was not in writing state (State: \(micWriter.status.rawValue)). Finalization skipped.")
             } else {
                 print("MicrophoneRecorder: Mic writer not available. Finalization skipped.")
             }
             // Reset potentially partially initialized writer/input
             self.micWriter = nil
             self.micWriterInput = nil
        }

        // Wait for finishWriting (with a timeout like the original)
        let result = dispatchGroup.wait(timeout: .now() + 3.0) // Use 3 sec timeout like original closeVideo
        if result == .timedOut {
            print("MicrophoneRecorder: Warning: Mic writer finalization timed out.")
            // Force cleanup of references even if timed out
             self.micWriter = nil
             self.micWriterInput = nil
        }
        
        // outputURL is kept until next recording starts
        print("MicrophoneRecorder: Stop recording process complete.")
    }


    private func setMicrophoneAsDefault(captureDevice: AVCaptureDevice) {
        // (This function remains exactly the same as in the original file)
        // Find the device ID that matches this capture device
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var propertySize: UInt32 = 0
        var status = AudioObjectGetPropertyDataSize(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            &propertySize
        )

        if status != noErr {
             print("MicrophoneRecorder: Error getting size for audio devices: \(status)")
            return
        }

        let deviceCount = Int(propertySize) / MemoryLayout<AudioDeviceID>.size
        var deviceIDs = [AudioDeviceID](repeating: 0, count: deviceCount)

        status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            &propertySize,
            &deviceIDs
        )

        if status != noErr {
            print("MicrophoneRecorder: Error getting audio device IDs: \(status)")
            return
        }

        // Find the matching device by UID
        for deviceID in deviceIDs {
            // Correctly handle CFString property using UnsafeMutablePointer
            let cfUID = UnsafeMutablePointer<Unmanaged<CFString>?>.allocate(capacity: 1)
            defer { cfUID.deallocate() }

            var propAddress = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyDeviceUID,
                mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain
            )

            var uidSize = UInt32(MemoryLayout<CFString?>.size) // Use size of pointer

            // Get the device UID
             let uidStatus = AudioObjectGetPropertyData(
                 deviceID,
                 &propAddress,
                 0,
                 nil,
                 &uidSize,
                 cfUID // Pass the pointer to the pointer
             )


             if uidStatus == noErr, let uidPtr = cfUID.pointee { // Check if pointer is non-nil
                 let uidRef = uidPtr.takeRetainedValue() // Now safe to retain
                 // Convert the CFString to a Swift String
                let deviceUIDString = uidRef as String

                if deviceUIDString == captureDevice.uniqueID {
                    // Found matching device, set as default input
                    var defaultAddress = AudioObjectPropertyAddress(
                        mSelector: kAudioHardwarePropertyDefaultInputDevice,
                        mScope: kAudioObjectPropertyScopeGlobal,
                        mElement: kAudioObjectPropertyElementMain
                    )

                    var mutableDeviceID = deviceID // Make mutable copy

                    let setStatus = AudioObjectSetPropertyData( // Capture status
                        AudioObjectID(kAudioObjectSystemObject),
                        &defaultAddress,
                        0,
                        nil,
                        UInt32(MemoryLayout<AudioDeviceID>.size),
                        &mutableDeviceID // Pass address of mutable copy
                    )

                     if setStatus == noErr {
                        print("MicrophoneRecorder: Set default input device to: \(captureDevice.localizedName)")
                     } else {
                         print("MicrophoneRecorder: Failed to set default input device. Status: \(setStatus)")
                     }
                    break // Exit loop once found and attempted set
                }
             } else {
                 // Handle error getting UID if needed, but often just skip device
                 // print("MicrophoneRecorder: Could not get UID for device ID \(deviceID), status: \(uidStatus)")
             }
        }
    }
}


// MARK: - Buffer Extensions (Moved Here)
// Keep the extension name the same as original for consistency
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
        ) == noErr else {
            print("MicrophoneRecorder Ext: Failed CMAudioFormatDescriptionCreate")
            return nil
        }

        var timing = CMSampleTimingInfo(
            duration: CMTime(value: 1, timescale: Int32(asbd.pointee.mSampleRate)),
            presentationTimeStamp: CMClockGetTime(CMClockGetHostTimeClock()), // Use host time clock as original
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
        ) == noErr else {
             print("MicrophoneRecorder Ext: Failed CMSampleBufferCreate")
             return nil
         }

        guard let createdSampleBuffer = sampleBuffer, // Ensure non-nil before using
              CMSampleBufferSetDataBufferFromAudioBufferList(
                  createdSampleBuffer, // Use the non-optional buffer
                  blockBufferAllocator: kCFAllocatorDefault,
                  blockBufferMemoryAllocator: kCFAllocatorDefault,
                  flags: 0,
                  bufferList: self.mutableAudioBufferList
              ) == noErr else {
            print("MicrophoneRecorder Ext: Failed CMSampleBufferSetDataBufferFromAudioBufferList")
            return nil
        }

        return createdSampleBuffer // Return the created buffer
    }
}
