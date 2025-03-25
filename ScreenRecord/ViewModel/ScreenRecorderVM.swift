// ScreenRecorderVM.swift
//
//import Foundation
//import SwiftUI
//import Combine
//import ScreenCaptureKit
//
//class ScreenRecorderViewModel: ObservableObject {
//    // MARK: - Published Properties
//    @Published var isRecording: Bool = false
//    @Published var isPreparing: Bool = false
//    @Published var isPermissionGranted: Bool = false
//    @Published var errorMessage: String?
//    @Published var recordingURL: URL?
//    @Published var microphoneURL: URL?
//    @Published var enhancedAudioURL: URL?
//    @Published var displays: [SCDisplay] = []
//    @Published var isProcessingAudio: Bool = false
//    
//    // MARK: - Private Properties
//    private let recorder = ScreenRecorderWithSepMic()
//    private var cancellables = Set<AnyCancellable>()
//    private var denoiser: AudioDenoiser?
//    
//    // MARK: - Initialization
//    init() {
//        setupDenoiser()
//        setupBindings()
//        requestPermission()
//    }
//    
//    // MARK: - Public Methods
//    func startRecording() {
//        errorMessage = nil
//        recorder.startRecording()
//    }
//    
//    func stopRecording() {
//        recorder.stopRecording()
//    }
//    
//    func requestPermission() {
//        recorder.requestPermission()
//    }
//    
//    func checkMicrophonePermission() {
//        recorder.requestMicrophonePermission { [weak self] granted in
//            if granted {
//                print("Microphone permission granted")
//                // You can set a flag here to enable microphone recording
//                // self?.recorder.enableMicrophone(true)
//            } else {
//                print("Microphone permission denied")
//                self?.errorMessage = "Microphone permission is required for audio recording"
//            }
//        }
//    }
//    
//    func enhanceAudio() {
//        guard let microphoneURL = microphoneURL, !isProcessingAudio, !isRecording else { return }
//        
//        isProcessingAudio = true
//        errorMessage = nil
//        
//        // Run on background thread
//        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
//            guard let self = self, let denoiser = self.denoiser else {
//                DispatchQueue.main.async {
//                    self?.isProcessingAudio = false
//                    self?.errorMessage = "Denoiser not available"
//                }
//                return
//            }
//            
//            denoiser.denoiseFile(inputFileURL: microphoneURL) { outputURL in
//                DispatchQueue.main.async {
//                    self.isProcessingAudio = false
//                    
//                    if let outputURL = outputURL {
//                        do {
//                            // Create a copy in the downloads folder with a better name
//                            let downloadDir = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first!
//                            let originalFileName = microphoneURL.deletingPathExtension().lastPathComponent
//                            let enhancedFileName = "enhanced_\(originalFileName).wav"
//                            let finalURL = downloadDir.appendingPathComponent(enhancedFileName)
//                            
//                            // Remove existing file if it exists
//                            if FileManager.default.fileExists(atPath: finalURL.path) {
//                                try FileManager.default.removeItem(at: finalURL)
//                            }
//                            
//                            // Copy the enhanced file to downloads
//                            try FileManager.default.copyItem(at: outputURL, to: finalURL)
//                            
//                            self.enhancedAudioURL = finalURL
//                            print("Enhanced audio saved to: \(finalURL.path)")
//                        } catch {
//                            self.errorMessage = "Error saving enhanced audio: \(error.localizedDescription)"
//                            print("Error saving enhanced audio: \(error)")
//                        }
//                    } else {
//                        self.errorMessage = "Audio processing failed"
//                    }
//                }
//            }
//        }
//    }
//    
//    // MARK: - Private Methods
//    private func setupDenoiser() {
//        if let binaryURL = Bundle.main.url(forResource: "deep-filter-aarch64-apple-darwin", withExtension: "") {
//            denoiser = AudioDenoiser(binaryURL: binaryURL)
//        } else {
//            print("Error: Could not find denoiser binary in app bundle")
//        }
//    }
//    
//    private func setupBindings() {
//        // Bind recorder state changes to our published properties
//        recorder.$state
//            .receive(on: DispatchQueue.main)
//            .sink { [weak self] state in
//                guard let self = self else { return }
//                
//                switch state {
//                case .idle:
//                    self.isRecording = false
//                    self.isPreparing = false
//                case .preparing:
//                    self.isPreparing = true
//                    self.isRecording = false
//                    // Reset enhanced audio URL when starting a new recording
//                    self.enhancedAudioURL = nil
//                case .recording:
//                    self.isRecording = true
//                    self.isPreparing = false
//                case .error(let error):
//                    self.isRecording = false
//                    self.isPreparing = false
//                    self.errorMessage = error.localizedDescription
//                }
//            }
//            .store(in: &cancellables)
//        
//        // Bind available displays
//        recorder.$displays
//            .receive(on: DispatchQueue.main)
//            .sink { [weak self] displays in
//                self?.displays = displays
//                self?.isPermissionGranted = !displays.isEmpty
//            }
//            .store(in: &cancellables)
//        
//        // Bind output URL
//        recorder.$outputURL
//            .receive(on: DispatchQueue.main)
//            .sink { [weak self] url in
//                self?.recordingURL = url
//            }
//            .store(in: &cancellables)
//        
//        // Bind microphone URL
//        recorder.$micOutputURL
//            .receive(on: DispatchQueue.main)
//            .sink { [weak self] url in
//                self?.microphoneURL = url
//                // Reset enhanced audio URL when a new mic recording is available
//                if url != nil {
//                    self?.enhancedAudioURL = nil
//                }
//            }
//            .store(in: &cancellables)
//    }
//}



import Foundation
import SwiftUI
import Combine
import ScreenCaptureKit

class ScreenRecorderViewModel: ObservableObject {
    // MARK: - Published Properties
    @Published var isRecording: Bool = false
    @Published var isPreparing: Bool = false
    @Published var isPermissionGranted: Bool = false
    @Published var errorMessage: String?
    @Published var recordingURL: URL?
    @Published var microphoneURL: URL?
    @Published var enhancedAudioURL: URL?
    @Published var displays: [SCDisplay] = []
    @Published var isProcessingAudio: Bool = false
    @Published var showRecordingInfo: Bool = false  // New flag to control when recording info is shown
    
    // MARK: - Private Properties
    private let recorder = ScreenRecorderWithSepMic()
    private var cancellables = Set<AnyCancellable>()
    private var denoiser: AudioDenoiser?
    
    // MARK: - Initialization
    init() {
        setupDenoiser()
        setupBindings()
        requestPermission()
    }
    
    // MARK: - Public Methods
    func startRecording() {
        errorMessage = nil
        
        // Reset URLs and hide recording info before starting
        showRecordingInfo = false
        isPreparing = true
        
        recorder.startRecording()
    }
    
    func stopRecording() {
        recorder.stopRecording()
    }
    
    func requestPermission() {
        recorder.requestPermission()
    }
    
    func checkMicrophonePermission() {
        recorder.requestMicrophonePermission { [weak self] granted in
            if granted {
                print("Microphone permission granted")
                // You can set a flag here to enable microphone recording
                // self?.recorder.enableMicrophone(true)
            } else {
                print("Microphone permission denied")
                self?.errorMessage = "Microphone permission is required for audio recording"
            }
        }
    }
    
    
    // Denoiser: remove background noise.
    func enhanceAudio() {
        guard let microphoneURL = microphoneURL, !isProcessingAudio, !isRecording else { return }
        
        isProcessingAudio = true
        errorMessage = nil
        
        denoiser?.enhanceAudio(inputURL: microphoneURL) { [weak self] finalURL in
            DispatchQueue.main.async {
                self?.isProcessingAudio = false
                if let finalURL = finalURL {
                    self?.enhancedAudioURL = finalURL
                    print("Enhanced audio saved to: \(finalURL.path)")
                } else {
                    self?.errorMessage = "Audio processing failed"
                }
            }
        }
    }
    
    // MARK: - Private Methods
    private func setupDenoiser() {
        if let binaryURL = Bundle.main.url(forResource: "deep-filter-aarch64-apple-darwin", withExtension: "") {
            denoiser = AudioDenoiser(binaryURL: binaryURL)
        } else {
            print("Error: Could not find denoiser binary in app bundle")
        }
    }
    
    private func setupBindings() {
        // Bind recorder state changes to our published properties
        recorder.$state
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state in
                guard let self = self else { return }
                
                switch state {
                case .idle:
                    self.isRecording = false
                    self.isPreparing = false
                    
                    // Only show recording info when we've completed a recording
                    if self.recordingURL != nil {
                        self.showRecordingInfo = true
                    }
                    
                case .preparing:
                    self.isPreparing = true
                    self.isRecording = false
                    // Reset enhanced audio URL when starting a new recording
                    self.enhancedAudioURL = nil
                    
                case .recording:
                    self.isRecording = true
                    self.isPreparing = false
                    
                case .error(let error):
                    self.isRecording = false
                    self.isPreparing = false
                    self.errorMessage = error.localizedDescription
                }
            }
            .store(in: &cancellables)
        
        // Bind available displays
        recorder.$displays
            .receive(on: DispatchQueue.main)
            .sink { [weak self] displays in
                self?.displays = displays
                self?.isPermissionGranted = !displays.isEmpty
            }
            .store(in: &cancellables)
        
        // Bind output URL
        recorder.$outputURL
            .receive(on: DispatchQueue.main)
            .sink { [weak self] url in
                self?.recordingURL = url
            }
            .store(in: &cancellables)
        
        // Bind microphone URL
        recorder.$micOutputURL
            .receive(on: DispatchQueue.main)
            .sink { [weak self] url in
                self?.microphoneURL = url
                // Reset enhanced audio URL when a new mic recording is available
                if url != nil {
                    self?.enhancedAudioURL = nil
                }
            }
            .store(in: &cancellables)
    }
}
