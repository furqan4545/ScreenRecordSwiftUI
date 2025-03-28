// ScreenRecorderVM.swift


import Foundation
import SwiftUI
import Combine
import ScreenCaptureKit
import AVFoundation

class ScreenRecorderViewModel: ObservableObject {
    // MARK: - Published Properties
    @Published var isRecording: Bool = false
    @Published var isPreparing: Bool = false
    @Published var isPermissionGranted: Bool = false
    @Published var errorMessage: String?
    @Published var recordingURL: URL?
    @Published var microphoneURL: URL?
    @Published var cameraURL: URL?
    @Published var enhancedAudioURL: URL?
    @Published var cursorDataURL: URL?
    @Published var displays: [SCDisplay] = []
    @Published var isProcessingAudio: Bool = false
    @Published var showRecordingInfo: Bool = false
    
    // Camera related properties
    @Published var isCameraEnabled: Bool = false {
        didSet {
            // When camera is enabled, immediately prepare it
            if isCameraEnabled && !oldValue {
                cameraRecorder.prepareForRecording()
            } else if !isCameraEnabled && oldValue {
                // When camera is disabled, release resources
                cameraRecorder.releaseCamera()
                isCameraReady = false
            }
        }
    }
    @Published var availableCameras: [AVCaptureDevice] = []
    @Published var selectedCamera: AVCaptureDevice?
    @Published var isCameraReady: Bool = false
    
    // Cursor tracking properties
    @Published var isCursorTrackingEnabled: Bool = true  // Default to enabled
    @Published var currentCursorPosition: CGPoint = .zero
    
    // MARK: - Private Properties
    private let recorder = ScreenRecorderWithSepMic()
    private let cameraRecorder = CameraRecorder()
    private let cursorTracker = CursorTracker()  // Cursor tracker
    private var cancellables = Set<AnyCancellable>()
    private var denoiser: AudioDenoiser?
    
    // MARK: - Initialization
    init() {
        setupDenoiser()
        setupBindings()
        requestPermission()
        setupCameraBindings()
        setupCursorTrackerBindings()
    }
    
    // MARK: - Public Methods
    func startRecording() {
        errorMessage = nil
        
        // Reset URLs and hide recording info before starting
        showRecordingInfo = false
        isPreparing = true
        
        // If camera is enabled but not ready, prepare it and wait
        if isCameraEnabled && !isCameraReady {
            // Wait briefly for camera to initialize
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                self?.performRecording()
            }
        } else {
            // Start immediately if camera is ready or not used
            performRecording()
        }
    }
    
//    private func performRecording() {
//        // Start screen recording
//        recorder.startRecording()
//        
//        // Start camera recording if enabled
//        if isCameraEnabled && isCameraReady {
//            cameraRecorder.startRecording()
//        }
//    }
    private func performRecording() {
        // Start camera recording first if enabled
        if isCameraEnabled && isCameraReady {
            cameraRecorder.startRecording()
            
            // Add a 1-second delay before starting screen recording
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
                guard let self = self else { return }
                
                // Start screen recording after the delay
                self.recorder.startRecording()
                // Start cursor tracking if enabled
                if self.isCursorTrackingEnabled {
                    self.cursorTracker.startTracking()
                }
            }
        } else {
            // If no camera, start screen recording immediately
            recorder.startRecording()
            // Start cursor tracking if enabled
            if isCursorTrackingEnabled {
                cursorTracker.startTracking()
            }
        }
    }
    
    func stopRecording() {
        // Stop screen recording
        recorder.stopRecording()
        
        // Stop camera recording if it was started
        if isCameraEnabled {
            cameraRecorder.stopRecording()
        }
        
        // Stop cursor tracking if it was started
        if isCursorTrackingEnabled {
            cursorTracker.stopTracking()
        }
    }
    
    func toggleCursorTracking() {
        isCursorTrackingEnabled.toggle()
    }
    
    func requestPermission() {
        recorder.requestPermission()
    }
    
    func checkMicrophonePermission() {
        recorder.requestMicrophonePermission { [weak self] granted in
            if granted {
                print("Microphone permission granted")
            } else {
                print("Microphone permission denied")
                self?.errorMessage = "Microphone permission is required for audio recording"
            }
        }
    }
    
    func checkCameraPermission(completion: @escaping (Bool) -> Void) {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            completion(true)
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { granted in
                DispatchQueue.main.async {
                    completion(granted)
                }
            }
        case .denied, .restricted:
            completion(false)
            self.errorMessage = "Camera permission is required for camera recording"
        default:
            completion(false)
        }
    }
    
    func selectCamera(_ camera: AVCaptureDevice) {
        selectedCamera = camera
        cameraRecorder.selectCamera(camera)
        
        // Mark camera as not ready when selection changes
        isCameraReady = false
    }
    
    func toggleCamera() {
        if isCameraEnabled {
            isCameraEnabled = false
        } else {
            checkCameraPermission { [weak self] granted in
                if granted {
                    self?.isCameraEnabled = true
                    // This will trigger the didSet and prepare the camera
                }
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
    
    private func setupCursorTrackerBindings() {
        // Bind cursor position updates
        cursorTracker.$currentPosition
            .receive(on: DispatchQueue.main)
            .sink { [weak self] position in
                self?.currentCursorPosition = position
            }
            .store(in: &cancellables)
        
        // Bind recording state
        cursorTracker.$isRecording
            .receive(on: DispatchQueue.main)
            .sink { _ in
                // We don't need to do anything here, but we might want
                // to update UI elements based on cursor tracking state
            }
            .store(in: &cancellables)
        
        // Bind output URL
        cursorTracker.$outputURL
            .receive(on: DispatchQueue.main)
            .sink { [weak self] url in
                self?.cursorDataURL = url
            }
            .store(in: &cancellables)
    }
    
    private func setupCameraBindings() {
        // Bind camera recording URL
        cameraRecorder.$recordingURL
            .receive(on: DispatchQueue.main)
            .sink { [weak self] url in
                self?.cameraURL = url
            }
            .store(in: &cancellables)
        
        // Bind available cameras
        cameraRecorder.$availableCameras
            .receive(on: DispatchQueue.main)
            .sink { [weak self] cameras in
                self?.availableCameras = cameras
                if self?.selectedCamera == nil {
                    self?.selectedCamera = cameras.first
                }
            }
            .store(in: &cancellables)
        
        // Bind selected camera
        cameraRecorder.$selectedCamera
            .receive(on: DispatchQueue.main)
            .sink { [weak self] camera in
                self?.selectedCamera = camera
            }
            .store(in: &cancellables)
            
        // Bind camera ready state
        cameraRecorder.$isReady
            .receive(on: DispatchQueue.main)
            .sink { [weak self] isReady in
                self?.isCameraReady = isReady
            }
            .store(in: &cancellables)
    }
    
    // Clean up resources when the view model is deallocated
    deinit {
        if isCameraEnabled {
            cameraRecorder.releaseCamera()
        }
    }
}
