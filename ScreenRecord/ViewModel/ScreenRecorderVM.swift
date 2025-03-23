//
//  ScreenRecorderVM.swift
//  ScreenRecord
//
//  Created by Furqan Ali on 3/24/25.
//


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
    @Published var displays: [SCDisplay] = []
    
    // MARK: - Private Properties
    private let recorder = ScreenRecorder()
    private var cancellables = Set<AnyCancellable>()
    
    // MARK: - Initialization
    init() {
        setupBindings()
        requestPermission()
    }
    
    // MARK: - Public Methods
    func startRecording() {
        errorMessage = nil
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
    
    private func setupBindings() {
        // Bind recorder state changes to our published properties
        recorder.$state
            .receive(on: DispatchQueue.main) // Add this line
            .sink { [weak self] state in
                guard let self = self else { return }
                
                switch state {
                case .idle:
                    self.isRecording = false
                    self.isPreparing = false
                case .preparing:
                    self.isPreparing = true
                    self.isRecording = false
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
            .receive(on: DispatchQueue.main) // Add this line
            .sink { [weak self] displays in
                self?.displays = displays
                self?.isPermissionGranted = !displays.isEmpty
            }
            .store(in: &cancellables)
        
        // Bind output URL
        recorder.$outputURL
            .receive(on: DispatchQueue.main) // Add this line
            .sink { [weak self] url in
                self?.recordingURL = url
            }
            .store(in: &cancellables)
    }
}
