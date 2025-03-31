//
//  PermissionsView.swift
//  ScreenRecord
//
//  Created by Furqan Ali on 3/26/25.
//

import SwiftUI
import AVFoundation
import Cocoa
import ScreenCaptureKit

struct PermissionsView: View {
    @Binding var permissionsGranted: Bool
    @State private var currentStep = 1
    @State private var hiddenText = ""
    @State private var screenPermissionStatus = false
    @State private var microphonePermissionStatus = false
    @State private var accessibilityPermissionStatus = false
    
    var body: some View {
        ScrollView {
            VStack(spacing: 30) {
                headerView
                
                screenPermissionStep
                
                microphonePermissionStep
                
                accessibilityPermissionStep
                
                finalStep
                
                // Hidden text field to capture the simulated typing
                TextField("", text: $hiddenText)
                    .frame(width: 0, height: 0)
                    .opacity(0)
                
                progressIndicator
                
                navigationButtons
            }
            .padding(.horizontal, 30)
        }
        .frame(minWidth: 600, minHeight: 680)
        .onAppear {
            checkPermissionStatuses()
        }
    }
    
    // MARK: - Subviews
    
    private var headerView: some View {
        VStack(spacing: 15) {
            Spacer(minLength: 20)
            
            Image(systemName: "checkmark.shield.fill")
                .font(.system(size: 60))
                .foregroundColor(.blue)
            
            Text("Permissions Required")
                .font(.largeTitle)
                .fontWeight(.bold)
            
            Text("Screen Recorder needs a few permissions to work properly.\nFollow these steps to get started.")
                .font(.headline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
                .padding(.bottom, 10)
        }
    }
    
    private var screenPermissionStep: some View {
        PermissionStepView(
            number: 1,
            isActive: currentStep == 1,
            title: "Screen Recording Access",
            description: "The app needs screen recording access to capture your screen content."
        ) {
            HStack {
                Button(action: requestScreenPermission) {
                    Text("Allow Screen Recording")
                        .fontWeight(.semibold)
                        .frame(maxWidth: .infinity)
                        .frame(height: 44)
                        .background(Color.blue)
                        .foregroundColor(.white)
                        .cornerRadius(8)
                }
                .buttonStyle(PlainButtonStyle())
                
                if screenPermissionStatus {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                        .font(.title2)
                }
            }
        }
    }
    
    private var microphonePermissionStep: some View {
        PermissionStepView(
            number: 2,
            isActive: currentStep == 2,
            title: "Microphone Access",
            description: "The app needs microphone access to record audio during screen recording."
        ) {
            HStack {
                Button(action: requestMicrophonePermission) {
                    Text("Allow Microphone Access")
                        .fontWeight(.semibold)
                        .frame(maxWidth: .infinity)
                        .frame(height: 44)
                        .background(Color.blue)
                        .foregroundColor(.white)
                        .cornerRadius(8)
                }
                .buttonStyle(PlainButtonStyle())
                
                if microphonePermissionStatus {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                        .font(.title2)
                }
            }
        }
    }
    
    private var accessibilityPermissionStep: some View {
        PermissionStepView(
            number: 3,
            isActive: currentStep == 3,
            title: "Accessibility Access",
            description: "This permission is required to track cursor and keyboard activity during recording. When prompted, click 'Allow' in the system dialog."
        ) {
            VStack(spacing: 12) {
                HStack {
                    Button(action: triggerAccessibilityPermission) {
                        Text("Enable Accessibility Access")
                            .fontWeight(.semibold)
                            .frame(maxWidth: .infinity)
                            .frame(height: 44)
                            .background(Color.blue)
                            .foregroundColor(.white)
                            .cornerRadius(8)
                    }
                    .buttonStyle(PlainButtonStyle())
                    
                    if accessibilityPermissionStatus {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                            .font(.title2)
                    }
                }
                
                Button(action: checkAccessibilityPermission) {
                    Text("Check Permission Status")
                        .fontWeight(.medium)
                        .frame(maxWidth: .infinity)
                        .frame(height: 44)
                        .background(Color.gray.opacity(0.2))
                        .foregroundColor(.primary)
                        .cornerRadius(8)
                }
                .buttonStyle(PlainButtonStyle())
                .padding(.top, 8)
            }
        }
    }
    
    private var finalStep: some View {
        PermissionStepView(
            number: 4,
            isActive: currentStep == 4,
            title: "You're All Set!",
            description: "You've completed the necessary setup. Click continue to start using Screen Recorder."
        ) {
            Button(action: {
                // Save status to UserDefaults and continue
                UserDefaults.standard.set(true, forKey: "permissionsGranted")
                permissionsGranted = true
            }) {
                Text("Continue to App")
                    .fontWeight(.semibold)
                    .frame(maxWidth: .infinity)
                    .frame(height: 44)
                    .background(Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(8)
            }
            .buttonStyle(PlainButtonStyle())
        }
    }
    
    private var progressIndicator: some View {
        HStack(spacing: 20) {
            ForEach(1...4, id: \.self) { step in
                Circle()
                    .fill(step <= currentStep ? Color.blue : Color.gray.opacity(0.3))
                    .frame(width: 10, height: 10)
            }
        }
        .padding(.top, 20)
        .padding(.bottom, 30)
    }
    
    private var navigationButtons: some View {
        HStack {
            if currentStep > 1 {
                Button("Back") {
                    currentStep -= 1
                }
                .buttonStyle(.bordered)
            }
            
            Spacer()
            
            if currentStep < 4 {
                Button("Next") {
                    currentStep += 1
                }
                .buttonStyle(.bordered)
                .disabled(
                    (currentStep == 1 && !screenPermissionStatus) ||
                    (currentStep == 2 && !microphonePermissionStatus) ||
                    (currentStep == 3 && !accessibilityPermissionStatus)
                )
            }
        }
        .padding(.horizontal, 50)
    }
    
    // MARK: - Permission Methods
    
    private func checkPermissionStatuses() {
        // Check screen recording permission
        Task {
            do {
                let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
                DispatchQueue.main.async {
                    screenPermissionStatus = !content.displays.isEmpty
                    if screenPermissionStatus && currentStep == 1 {
                        currentStep = 2
                    }
                }
            } catch {
                print("Screen recording permission not granted")
            }
        }
        
        // Check microphone permission
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            microphonePermissionStatus = true
            if currentStep == 2 {
                currentStep = 3
            }
        default:
            microphonePermissionStatus = false
        }
        
        // Check accessibility permission
        checkAccessibilityPermission()
    }
    
    private func requestScreenPermission() {
        Task {
            do {
                let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
                DispatchQueue.main.async {
                    screenPermissionStatus = !content.displays.isEmpty
                    if screenPermissionStatus {
                        currentStep = 2
                    }
                }
            } catch {
                // If error, open system preferences
                let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")
                if let url = url {
                    NSWorkspace.shared.open(url)
                }
            }
        }
    }
    
    private func requestMicrophonePermission() {
        AVCaptureDevice.requestAccess(for: .audio) { granted in
            DispatchQueue.main.async {
                microphonePermissionStatus = granted
                if granted {
                    currentStep = 3
                }
            }
        }
    }
    
    private func triggerAccessibilityPermission() {
        // First attempt to simulate a key press to trigger the permission dialog
        KeyboardSimulator.simulateKeyPress()
        
        // Then open System Preferences/Settings directly
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            if #available(macOS 13, *) {
                let settingsURL = URL(string: "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_Accessibility")
                if let url = settingsURL {
                    NSWorkspace.shared.open(url)
                } else {
                    let prefpaneURL = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
                    NSWorkspace.shared.open(prefpaneURL)
                }
            } else {
                let prefpaneURL = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
                NSWorkspace.shared.open(prefpaneURL)
            }
        }
    }
    
    private func checkAccessibilityPermission() {
        // Check if we have accessibility permissions
        let isGranted = AXIsProcessTrusted()
        
        DispatchQueue.main.async {
            accessibilityPermissionStatus = isGranted
            if isGranted && currentStep == 3 {
                currentStep = 4
            }
        }
        
        // Make a concrete accessibility API call to ensure the app shows up in the list
        var observer: AXObserver?
        let pid = ProcessInfo.processInfo.processIdentifier
        let status = AXObserverCreate(pid, { _, _, _, _ in }, &observer)
        
        if status == .success, let observer = observer {
            CFRunLoopAddSource(CFRunLoopGetMain(),
                             AXObserverGetRunLoopSource(observer),
                             .defaultMode)
        }
    }
}
