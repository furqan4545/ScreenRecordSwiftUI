// ContentView.swift

import SwiftUI
import ScreenCaptureKit
import AVFoundation
import Cocoa

struct ContentView: View {
    @EnvironmentObject var viewModel: ScreenRecorderViewModel
    
    // MARK: Display Manager for plotting overlay windows.
    @Environment(\.openWindow) private var openWindow
    
    @EnvironmentObject private var screenSelectionManager: ScreenSelectionManager
    @State private var showingSelectionInfo = false
    
    
    // Initial position for the floating stop button.
    @State private var stopButtonPosition: CGPoint = CGPoint(x: 150, y: 150)
    
    
    // Add this function to your ContentView
    private func testAreaSelection() {
        // Start by opening overlays on all screens
        screenSelectionManager.startAreaSelection()
        
        let screens = NSScreen.screens
        let count = min(screens.count, 6) // Reasonable limit
        for index in 0..<count {
            openWindow(id: "dynamic-display", value: index)
        }
        
        // Set up observation of selection confirmation
        // This is important for testing the area selection
        setupSelectionObserver()
    }

    // Add this function to monitor selection status
    private func setupSelectionObserver() {
        // Start observing the selection manager
        // In a real app you might use Combine for this
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            if !screenSelectionManager.isSelectionInProgress {
                // We're done with selection process
                if screenSelectionManager.isSelectionConfirmed,
                   let _ = screenSelectionManager.selectedArea {
                    // Selection was confirmed - show info
                    showingSelectionInfo = true
                }
                return
            }
            
            // Keep checking until selection completes
            setupSelectionObserver()
        }
    }
    
    var body: some View {
        VStack(spacing: 20) {
            title
            
            if viewModel.isPermissionGranted {
                recordingOptions
                    .padding(.bottom, 5)
                
                recordingControls
                    .padding(.vertical)
                
                if let errorMessage = viewModel.errorMessage {
                    errorView(message: errorMessage)
                }
                
                if viewModel.showRecordingInfo && !viewModel.isRecording && !viewModel.isPreparing {
                    if let url = viewModel.recordingURL {
                        recordingInfoView(url: url)
                    }
                }
            } else {
                permissionView
            }
        }
        .padding()
        .frame(width: 500, height: 380)  // Adjusted height without input tracking options
        .disabled(viewModel.isProcessingAudio) // Disable entire UI during processing
        .overlay {
            if viewModel.isProcessingAudio {
                processingOverlay
            }
        }
    }
    
    // MARK: - View Components
    private var title: some View {
        Text("Screen Recorder")
            .font(.largeTitle)
            .fontWeight(.bold)
    }
    
    private var recordingOptions: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Camera options
            HStack {
                Toggle("Enable Camera Recording", isOn: $viewModel.isCameraEnabled)
                    .toggleStyle(.switch)
                    .disabled(viewModel.isRecording || viewModel.isPreparing)
                
                if viewModel.isCameraEnabled {
                    // Camera status indicator
                    if !viewModel.isCameraReady {
                        HStack(spacing: 5) {
                            ProgressView()
                                .scaleEffect(0.7)
                            Text("Initializing...")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    } else {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                            .font(.caption)
                    }
                }
            }
            
            if viewModel.isCameraEnabled, !viewModel.availableCameras.isEmpty {
                HStack {
                    Text("Camera:")
                        .font(.subheadline)
                    
                    Picker("", selection: Binding(
                        get: { viewModel.selectedCamera },
                        set: { camera in
                            if let camera = camera {
                                viewModel.selectCamera(camera)
                            }
                        }
                    )) {
                        ForEach(viewModel.availableCameras, id: \.uniqueID) { camera in
                            Text(camera.localizedName)
                                .tag(camera as AVCaptureDevice?)
                        }
                    }
                    .frame(maxWidth: 200)
                    .disabled(viewModel.isRecording || viewModel.isPreparing)
                }
                .padding(.leading, 20)
            }
            
            // Microphone options
            Divider()
                .padding(.vertical, 5)
            
            HStack {
                Toggle("Enable Microphone Recording", isOn: $viewModel.isMicrophoneEnabled)
                    .toggleStyle(.switch)
                    .disabled(viewModel.isRecording || viewModel.isPreparing)
                
                if viewModel.isMicrophoneEnabled {
                    // Microphone status indicator
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                        .font(.caption)
                }
            }

            if viewModel.isMicrophoneEnabled, !viewModel.availableMicrophones.isEmpty {
                HStack {
                    Text("Microphone:")
                        .font(.subheadline)
                    
                    Picker("", selection: Binding(
                        get: { viewModel.selectedMicrophone },
                        set: { microphone in
                            if let microphone = microphone {
                                viewModel.selectMicrophone(microphone)
                            }
                        }
                    )) {
                        ForEach(viewModel.availableMicrophones, id: \.uniqueID) { microphone in
                            Text(microphone.localizedName)
                                .tag(microphone as AVCaptureDevice?)
                        }
                    }
                    .frame(maxWidth: 200)
                    .disabled(viewModel.isRecording || viewModel.isPreparing)
                }
                .padding(.leading, 20)
            }
            
            // Add HDR toggle section here
            Divider()
                .padding(.vertical, 5)
            
            HStack {
                Toggle("Enable HDR Recording", isOn: $viewModel.isHDREnabled)
                    .toggleStyle(.switch)
                    .disabled(viewModel.isRecording || viewModel.isPreparing)
                
                if viewModel.isHDREnabled {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                        .font(.caption)
                }
            }
            .help("Records in High Dynamic Range for better color and brightness")
            
            // Recording Mode Section
            Divider()
                .padding(.vertical, 5)
            
            VStack(alignment: .leading, spacing: 8) {
                Text("Recording Mode:")
                    .font(.headline)
                
        
                
                HStack(spacing: 15) {
                    /// Window Picker Button
                    Button {
                        if viewModel.isRecording {
                            viewModel.stopRecording()
                        } else {
                            viewModel.startWindowSelection()
                        }
                    } label: {
                        Text(viewModel.isRecording ? "Stop Recording" : "Choose Window")
                            .fontWeight(.semibold)
                            .foregroundStyle(.background)
                            .padding(.vertical, 8)
                            .padding(.horizontal, 20)
                            .background(Color.primary.gradient, in: .rect(cornerRadius: 8))
                    }
                    .buttonStyle(.plain)
                    .disabled(viewModel.isPreparing)
                    
                    // Display Picker Button (NEW)
                    Button {
                        if viewModel.isRecording {
                            viewModel.stopRecording()
                        } else {
                            viewModel.startDisplaySelection()
                        }
                    } label: {
                        Text(viewModel.isRecording ? "Stop Recording" : "Choose Display")
                            .fontWeight(.semibold)
                            .foregroundStyle(.background)
                            .padding(.vertical, 8)
                            .padding(.horizontal, 20)
                            .background(Color.blue.gradient, in: .rect(cornerRadius: 8))
                    }
                    .buttonStyle(.plain)
                    .disabled(viewModel.isPreparing)
                    
                    // Area Picker Button (NEW)
                    Button("Test Area Selection") {
                        testAreaSelection()
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(screenSelectionManager.isSelectionInProgress)
                    .padding()
                    
                    /// Quit Button
                    Button("Quit") {
                        NSApplication.shared.terminate(nil)
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 10)
                }
                
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal)
        .onChange(of: viewModel.isRecording) {_, recording  in
            if recording {
                openWindow(id: "stopButton")
            }
        }
    }
    
    private var processingOverlay: some View {
        VStack {
            ProgressView()
                .scaleEffect(1.5)
                .padding()
            
            Text("Enhancing audio...")
                .font(.headline)
        }
        .padding()
        .background(Color(NSColor.windowBackgroundColor).opacity(0.9))
        .cornerRadius(10)
        .shadow(radius: 5)
    }
    
    private var recordingControls: some View {
        VStack(spacing: 15) {
            HStack(spacing: 20) {
                Button(action: {
                    viewModel.startRecording()
                }) {
                    HStack {
                        Image(systemName: "record.circle")
                        Text("Start Recording")
                    }
                    .frame(width: 150)
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
                .disabled(viewModel.isRecording || viewModel.isPreparing || (viewModel.isCameraEnabled && !viewModel.isCameraReady))
                
                Button(action: {
                    viewModel.stopRecording()
                }) {
                    HStack {
                        Image(systemName: "stop.circle")
                        Text("Stop Recording")
                    }
                    .frame(width: 150)
                }
                .buttonStyle(.bordered)
                .disabled(!viewModel.isRecording)
            }
            
            // Status text
            if viewModel.isPreparing {
                Text("Preparing recording...")
                    .font(.caption)
                    .foregroundColor(.secondary)
            } else if viewModel.isRecording {
                Text("Recording in progress...")
                    .font(.caption)
                    .foregroundColor(.red)
            } else if viewModel.isCameraEnabled && !viewModel.isCameraReady {
                Text("Waiting for camera to initialize...")
                    .font(.caption)
                    .foregroundColor(.orange)
            }
        }
        .overlay {
            if viewModel.isPreparing {
                ProgressView()
                    .scaleEffect(1.5)
                    .padding()
                    .background(Color.black.opacity(0.2))
                    .cornerRadius(10)
            }
        }
    }
    
    private var permissionView: some View {
        VStack(spacing: 15) {
            Image(systemName: "lock.shield")
                .font(.system(size: 40))
                .foregroundColor(.orange)
            
            Text("Screen Recording Permission Required")
                .font(.headline)
            
            Text("This app needs permission to record your screen.")
                .font(.subheadline)
                .multilineTextAlignment(.center)
                .foregroundColor(.secondary)
            
            Button("Request Permission") {
                viewModel.requestPermission()
            }
            .buttonStyle(.borderedProminent)
            
            Button("Enable Microphone") {
                viewModel.checkMicrophonePermission()
            }
            .buttonStyle(.bordered)
            .padding(.top, 5)
            
            Button("Enable Camera") {
                viewModel.toggleCamera()
            }
            .buttonStyle(.bordered)
            .padding(.top, 5)
        }
        .padding()
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(12)
        .shadow(radius: 2)
    }
    
    private func errorView(message: String) -> some View {
        HStack {
            Image(systemName: "exclamationmark.triangle")
                .foregroundColor(.red)
            Text(message)
                .font(.callout)
                .foregroundColor(.red)
        }
        .padding()
        .background(Color.red.opacity(0.1))
        .cornerRadius(8)
    }
    
    private func recordingInfoView(url: URL) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("Last Recording:")
                .font(.headline)
            
            HStack {
                Text(url.lastPathComponent)
                    .font(.callout)
                    .lineLimit(1)
                    .truncationMode(.middle)
                if url.lastPathComponent.contains("-HDR") {
                    Text("HDR")
                        .font(.caption)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 2)
                        .background(Color.yellow.opacity(0.3))
                        .cornerRadius(4)
                }
                
                // Add Window indicator if applicable
                if url.lastPathComponent.contains("-Window") {
                    Text("Window")
                        .font(.caption)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 2)
                        .background(Color.blue.opacity(0.3))
                        .cornerRadius(4)
                }
                    
                Spacer()
                
                Button {
                    NSWorkspace.shared.activateFileViewerSelecting([url])
                } label: {
                    Image(systemName: "folder")
                    Text("Show in Finder")
                }
                .buttonStyle(.plain)
                .foregroundColor(.blue)
            }
            
            if let micURL = viewModel.microphoneURL {
                Divider()
                
                HStack(alignment: .top) {
                    VStack(alignment: .leading) {
                        Text("Microphone Recording:")
                            .font(.headline)
                            .padding(.top, 5)
                        
                        Text(micURL.lastPathComponent)
                            .font(.callout)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    
                    Spacer()
                    
                    VStack(alignment: .trailing) {
                        Button {
                            NSWorkspace.shared.activateFileViewerSelecting([micURL])
                        } label: {
                            Image(systemName: "folder")
                            Text("Show in Finder")
                        }
                        .buttonStyle(.plain)
                        .foregroundColor(.blue)
                        
                        Button {
                            viewModel.enhanceAudio()
                        } label: {
                            Image(systemName: "wand.and.stars")
                            Text("Enhance Audio")
                        }
                        .buttonStyle(.plain)
                        .foregroundColor(.purple)
                        .padding(.top, 5)
                        .disabled(viewModel.isProcessingAudio || viewModel.isRecording)
                    }
                }
            }
            
            if let cameraURL = viewModel.cameraURL {
                Divider()
                
                Text("Camera Recording:")
                    .font(.headline)
                    .padding(.top, 5)
                
                HStack {
                    Text(cameraURL.lastPathComponent)
                        .font(.callout)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    
                    Spacer()
                    
                    Button {
                        NSWorkspace.shared.activateFileViewerSelecting([cameraURL])
                    } label: {
                        Image(systemName: "folder")
                        Text("Show in Finder")
                    }
                    .buttonStyle(.plain)
                    .foregroundColor(.blue)
                }
            }
            
            if let enhancedURL = viewModel.enhancedAudioURL {
                Divider()
                
                Text("Enhanced Audio:")
                    .font(.headline)
                    .padding(.top, 5)
                
                HStack {
                    Text(enhancedURL.lastPathComponent)
                        .font(.callout)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .foregroundColor(.green)
                    
                    Spacer()
                    
                    Button {
                        NSWorkspace.shared.activateFileViewerSelecting([enhancedURL])
                    } label: {
                        Image(systemName: "folder")
                        Text("Show in Finder")
                    }
                    .buttonStyle(.plain)
                    .foregroundColor(.blue)
                }
            }
        }
        .padding()
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(8)
    }
}

#Preview {
    ContentView()
//        .environmentObject(ScreenRecorderV2())
}
