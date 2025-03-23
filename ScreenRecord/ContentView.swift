//
//  ContentView.swift
//  ScreenRecord
//
//  Created by Furqan Ali on 3/24/25.
//

import SwiftUI
import ScreenCaptureKit

struct ContentView: View {
    @StateObject private var viewModel = ScreenRecorderViewModel()
    
    var body: some View {
        VStack(spacing: 20) {
            title
            
            if viewModel.isPermissionGranted {
                recordingControls
                    .padding(.vertical)
                
                if let errorMessage = viewModel.errorMessage {
                    errorView(message: errorMessage)
                }
                
                if let url = viewModel.recordingURL, !viewModel.isRecording {
                    recordingInfoView(url: url)
                }
            } else {
                permissionView
            }
        }
        .padding()
        .frame(width: 500, height: 300)
    }
    
    // MARK: - View Components
    private var title: some View {
        Text("Screen Recorder")
            .font(.largeTitle)
            .fontWeight(.bold)
    }
    
    private var recordingControls: some View {
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
            .disabled(viewModel.isRecording || viewModel.isPreparing)
            
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
            Button("Enable Microphone") {
                viewModel.checkMicrophonePermission()
            }
            .buttonStyle(.borderedProminent)
            .padding(.top)
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
        }
        .padding()
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(8)
    }
}

#Preview {
    ContentView()
}
