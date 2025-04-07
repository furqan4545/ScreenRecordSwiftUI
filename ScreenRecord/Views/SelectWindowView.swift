//
//  SelectWindowView.swift
//  ScreenRecord
//
//  Created by Furqan Ali on 4/8/25.
//
//

import SwiftUI
import AppKit
import ScreenCaptureKit

struct SelectWindowView: View {
    let windowID: String
    @State private var nsWindow: NSWindow?

    var body: some View {
        VStack(spacing: 20) {
            Text("Window")
                .font(.title)
                .foregroundColor(.white)
            
            // Custom close button to close this overlay window.
            Button("Close") {
                nsWindow?.close()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(WindowAccessor { window in
            if let window = window, window != self.nsWindow {
                self.nsWindow = window
                
                // Here we will position our overlay on the target window
                Task {
                    do {
                        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
                        
                        // Find the window with matching ID
                        if let targetWindow = content.windows.first(where: { String($0.windowID) == windowID }) {
                            // Configure the window:
                            window.styleMask = [.borderless] // Remove standard chrome.
                            let targetFrame = targetWindow.frame
                            window.setFrame(targetFrame, display: true, animate: false)
                            window.alphaValue = 0.6  // Semi-transparent.
                            window.level = .screenSaver // Ensure it appears on top.
                            print("Overlay window for app: \(targetWindow.owningApplication?.applicationName ?? "Unknown")")
                        } else {
                            print("No window available for ID \(windowID)")
                            window.close()
                        }
                    } catch {
                        print("Error getting window information: \(error)")
                        window.close()
                    }
                }
            }
        })
    }
}
