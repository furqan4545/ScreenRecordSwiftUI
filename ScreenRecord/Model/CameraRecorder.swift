import AVFoundation
import Foundation

class CameraRecorder: NSObject, AVCaptureFileOutputRecordingDelegate {
    // MARK: - Properties
    private var captureSession: AVCaptureSession?
    private var videoDevice: AVCaptureDevice?
    private var videoInput: AVCaptureDeviceInput?
    private var movieFileOutput: AVCaptureMovieFileOutput?
    
    @Published var isRecording: Bool = false
    @Published var recordingURL: URL?
    @Published var availableCameras: [AVCaptureDevice] = []
    @Published var selectedCamera: AVCaptureDevice?
    @Published var isReady: Bool = false
    @Published var isInitializing: Bool = false
    
    // MARK: - Initialization
    override init() {
        super.init()
        setupCaptureSession()
    }
    
    // MARK: - Setup
    private func setupCaptureSession() {
        // Find available cameras
        availableCameras = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.builtInWideAngleCamera, .external],
            mediaType: .video,
            position: .unspecified
        ).devices
        
        // Default to front camera if available
        selectedCamera = availableCameras.first(where: { $0.position == .front }) ?? availableCameras.first
        
        captureSession = AVCaptureSession()
        captureSession?.sessionPreset = .high
        
        // Configure movie file output
        movieFileOutput = AVCaptureMovieFileOutput()
    }
    
    func configureSession() {
        guard let captureSession = captureSession else { return }
        
        isReady = false
        isInitializing = true
        
        // Run the potentially slow configuration on a background thread
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            
            // Stop session if it's running
            if captureSession.isRunning {
                captureSession.stopRunning()
            }
            
            // Remove existing inputs and outputs
            for input in captureSession.inputs {
                captureSession.removeInput(input)
            }
            
            for output in captureSession.outputs {
                captureSession.removeOutput(output)
            }
            
            // Configure video input only (no audio)
            if let videoDevice = self.selectedCamera {
                do {
                    self.videoInput = try AVCaptureDeviceInput(device: videoDevice)
                    if captureSession.canAddInput(self.videoInput!) {
                        captureSession.addInput(self.videoInput!)
                    }
                } catch {
                    print("Error setting camera input: \(error.localizedDescription)")
                }
            }
            
            // Add movie file output
            if let movieFileOutput = self.movieFileOutput, captureSession.canAddOutput(movieFileOutput) {
                captureSession.addOutput(movieFileOutput)
            }
            
            // Start the session to warm it up
            captureSession.startRunning()
            
            // Mark as ready on the main thread
            DispatchQueue.main.async {
                self.isReady = true
                self.isInitializing = false
                print("Camera is ready for recording")
            }
        }
    }
    
    // MARK: - Camera Selection
    func selectCamera(_ camera: AVCaptureDevice) {
        selectedCamera = camera
        configureSession()
    }
    
    // MARK: - Preparation
    func prepareForRecording() {
        if !isReady && !isInitializing {
            configureSession()
        }
    }
    
    // MARK: - Resource cleanup
    func releaseCamera() {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self, let captureSession = self.captureSession else { return }
            
            // If recording, stop it first
            if self.isRecording {
                self.stopRecording()
            }
            
            // Stop the session
            if captureSession.isRunning {
                captureSession.stopRunning()
            }
            
            // Remove inputs and outputs
            for input in captureSession.inputs {
                captureSession.removeInput(input)
            }
            
            for output in captureSession.outputs {
                captureSession.removeOutput(output)
            }
            
            // Reset properties
            DispatchQueue.main.async {
                self.isReady = false
                self.isInitializing = false
                print("Camera resources released")
            }
        }
    }
    
    // MARK: - Recording Control
    func startRecording() {
        guard let _ = captureSession, !isRecording else { return }
        // If not ready, wait briefly for the camera to initialize
        if !isReady {
            print("Camera not ready yet, waiting...")
            return
        }
        
        // Create URL for camera recording
        let downloadsDirectory = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first!
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd-HH-mm-ss"
        let dateString = dateFormatter.string(from: Date())
        let url = downloadsDirectory.appendingPathComponent("Camera-Recording-\(dateString).mp4")
        
        // Start recording
        if let movieFileOutput = movieFileOutput {
            movieFileOutput.startRecording(to: url, recordingDelegate: self)
            isRecording = true
        }
    }
    
    func stopRecording() {
        guard isRecording else { return }
        
        // Stop recording
        if let movieFileOutput = movieFileOutput {
            movieFileOutput.stopRecording()
        }
    }
    
    // MARK: - AVCaptureFileOutputRecordingDelegate
    func fileOutput(_ output: AVCaptureFileOutput, didStartRecordingTo fileURL: URL, from connections: [AVCaptureConnection]) {
        // Recording started
        print("Camera recording started to: \(fileURL.path)")
    }
    
    func fileOutput(_ output: AVCaptureFileOutput, didFinishRecordingTo outputFileURL: URL, from connections: [AVCaptureConnection], error: Error?) {
        // Recording finished
        isRecording = false
        
        if let error = error {
            print("Error recording camera: \(error.localizedDescription)")
            return
        }
        
        recordingURL = outputFileURL
        print("Camera recording completed: \(outputFileURL.path)")
    }
    
    // MARK: - Cleanup
    deinit {
        releaseCamera()
    }
}
