// // ScreenRecorderVM.swift


///// ScreenRecorderVM.swift

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
    @Published var displays: [SCDisplay] = []
    @Published var isProcessingAudio: Bool = false
    @Published var showRecordingInfo: Bool = false
    @Published var isHDREnabled: Bool = true // Default to HDR enabled
    @Published var isInputTrackingEnabled: Bool = true
    
    // Add a published property to store the elapsed recording time (in seconds)
    @Published var elapsedTime: TimeInterval = 0
    // Timer publisher cancellable
    private var timerCancellable: AnyCancellable?
   
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
    
    // MARK: recording window or screen
    @Published var recordingMode: RecordingMode = .screen
    
    // MARK: - Private Properties
    private let recorder = ScreenRecorderWithHDR()
    private let cameraRecorder = CameraRecorder()
    private var cancellables = Set<AnyCancellable>()
    private var denoiser: AudioDenoiser?
    
    // private var cursorTracker: PollingCursorTracker?
    private var inputTracker: PollingCursorAndKeyboardTracker?
    
    // MARK: Window Tracker
    private let windowPickerManager = WindowPickerManager()
    
    // Instead of storing a concrete type or a closure,
    // declare a dependency with a protocol.
    private let selectionResetter: SelectionResettable
   
    // MARK: - Initialization
    init(selectionResetter: SelectionResettable) {
        self.selectionResetter = selectionResetter
        
        setupDenoiser()
        setupBindings()
        requestPermission()
        setupCameraBindings()
        setupWindowPickerBinding()
        // Initialize the recorder with the default HDR setting
        setHDRMode(isHDREnabled)
        setupCursorTracking()
        
    }
    
    // Add a property to track the current recording mode
    enum RecordingMode {
        case screen
        case window
        case display
    }
    
    
    // MARK: - Window Recording Methods
    // Method to start window selection
    func startWindowSelection() {
        recordingMode = .window
        startRecording() // This will show the picker
    }
    
    // Add a method for display selection
    func startDisplaySelection() {
        recordingMode = .display
        startRecording()
    }
    
    // Add a method for area selection
    func startAreaRecording(on display: SCDisplay, with selectionRect: CGRect) {
        print("area recording will receive it's param here like screen id and x,y,width and height")
        print("work to do here for area recording")
        if isCameraEnabled && isCameraReady {
            cameraRecorder.startRecording()
            
            // Add a 1-second delay before starting screen recording
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
                guard let self = self else { return }
                
                // Start screen recording after the delay
                self.recorder.startRecording(type: .area(display, selectionRect)) // Specify screen type
                
                startInputTrackingIfEnabled()
                self.startTimer()  // <-- Timer starts here
            }
        } else {
            // If no camera, start screen recording immediately
            self.recorder.startRecording(type: .area(display, selectionRect)) // Specify screen type
            startInputTrackingIfEnabled()
            self.startTimer()  // <-- Timer starts here
        }
    }
    
    
    // MARK: - Setup Window Picker.
    private func setupWindowPickerBinding() {
        windowPickerManager.onContentSelected = { [weak self] filter in
            guard let self = self else { return }
            
            // Immediately capture what we need before the Task
            let isEnabled = self.isCameraEnabled
            let isReady = self.isCameraReady
            
            // Dispatch back to main thread and handle everything there
            DispatchQueue.main.async {
                self.isPreparing = true
                // SET HDR MODE HERE (missing in original code)
                self.setHDRMode(self.isHDREnabled)
                
                // Start camera first if enabled
                if isEnabled && isReady {
                    self.cameraRecorder.startRecording()
                    
                    // Add a delay before starting window recording
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                        if self.recordingMode == .window {
                            self.recorder.startRecording(type: .window(filter))
                        } else {
                            self.recorder.startRecording(type: .display(filter))
                        }
                        // START INPUT TRACKING HERE (missing in original code)
                        self.startInputTrackingIfEnabled()
                        self.startTimer()  // <-- Timer starts here
                    }
                } else {
                    // If no camera, start window recording immediately
                    if self.recordingMode == .window {
                        self.recorder.startRecording(type: .window(filter))
                    } else {
                        self.recorder.startRecording(type: .display(filter))
                    }
                    // START INPUT TRACKING HERE TOO (missing in original code)
                    self.startInputTrackingIfEnabled()
                    self.startTimer()  // <-- Timer starts here
                }
            }
        }
        
        // Add a cancellation callback
        windowPickerManager.onPickerCancelled = { [weak self] in
            DispatchQueue.main.async {
                // Reset the preparing state when cancelled
                self?.isPreparing = false
            }
        }
    }
    
    
    // MARK: - Public Methods
    // Update the startRecording method to handle display selection
    func startRecording() {
        errorMessage = nil
        showRecordingInfo = false
        isPreparing = true
        
        switch recordingMode {
        case .window, .display:
            // Show picker based on mode
            windowPickerManager.showPicker(mode: recordingMode == .window ? .window : .display)
        
        case .screen:
            // Standard screen recording logic
            if isCameraEnabled && !isCameraReady {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                    self?.performRecording()
                }
            } else {
                performRecording()
            }
        }
    }
   
    
    private func performRecording() {
        // Ensure HDR setting is applied right before recording
        setHDRMode(isHDREnabled)
        
        // Start camera recording first if enabled
        if isCameraEnabled && isCameraReady {
            cameraRecorder.startRecording()
            
            // Add a 1-second delay before starting screen recording
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
                guard let self = self else { return }
                
                // Start screen recording after the delay
                self.recorder.startRecording(type: .screen) // Specify screen type
                startInputTrackingIfEnabled()
                
                // Start input tracking if needed…
                self.startTimer() // Start the timer when recording actually begins
            }
        } else {
            // If no camera, start screen recording immediately
            recorder.startRecording(type: .screen) // Specify screen type
            
            startInputTrackingIfEnabled()
            self.startTimer() // Start the timer immediately if no camera is enabled
        }
    }
   
    func stopRecording() {
        // Stop screen recording
        recorder.stopRecording()
        stopInputTracking()  // cursor tracking stop
        
        // Stop camera recording if it was started
        if isCameraEnabled {
            cameraRecorder.stopRecording()
        }
        
        // Cancel the timer when recording stops
        stopTimer()
        
        // Then explicitly use the dependency:
        selectionResetter.resetRecording()
    }
    
    // MARK: Timer methods
    private func startTimer() {
        // Reset the counter
        elapsedTime = 0
        timerCancellable?.cancel()
        // Create a timer that fires every second on the main run loop
        timerCancellable = Timer.publish(every: 1, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                guard let self = self, self.isRecording else { return }
                self.elapsedTime += 1
            }
    }
    
    private func stopTimer() {
        timerCancellable?.cancel()
        timerCancellable = nil
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

    func setHDRMode(_ enabled: Bool) {
        isHDREnabled = enabled
        recorder.setVideoQuality(enabled ? .hdr : .hd)
    }
    
    // Call this method in your init() function
    func setupCursorTracking() {
        // Initialize the cursor tracker
        inputTracker = PollingCursorAndKeyboardTracker(fps: 30, trackKeyboard: true)
    }
    
    // Start cursor tracking
    private func startInputTrackingIfEnabled() {
        if isInputTrackingEnabled {
            // Use Task to ensure this doesn't block recording
            Task.detached(priority: .background) {
                await MainActor.run {
                    // Get the video dimensions from the recorder
                    let videoWidth = self.recorder.recordedVideoWidth // You'll need to add these properties
                    let videoHeight = self.recorder.recordedVideoHeight
                    
                    self.inputTracker?.startTracking(videoWidth: videoWidth, videoHeight: videoHeight)
                }
            }
        }
    }

    // Stop cursor tracking
    private func stopInputTracking() {
        // Use Task to ensure this doesn't block stopping recording
        Task.detached(priority: .background) {
            await MainActor.run {
                self.inputTracker?.stopTracking()
            }
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
        
        $isHDREnabled
            .dropFirst() // Skip initial value to avoid redundant updates
            .sink { [weak self] enabled in
                self?.recorder.setVideoQuality(enabled ? .hdr : .hd)
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
        
        // Cancel all subscriptions
        cancellables.forEach { $0.cancel() }
        cancellables.removeAll()
    }
}
