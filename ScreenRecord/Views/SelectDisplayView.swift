//
//  SelectDisplayView.swift
//  ScreenRecord
//
//  Created by Furqan Ali on 4/1/25.
//
//


import SwiftUI
import AppKit

struct SelectDisplayView: View {
    let screenID: Int
    @State private var nsWindow: NSWindow?

    var body: some View {
        VStack(spacing: 20) {
            Text("Display \(screenID + 1)")
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
                let screens = NSScreen.screens
                if screens.indices.contains(screenID) {
                    // Configure the window:
                    window.styleMask = [.borderless] // Remove standard chrome.
                    let targetFrame = screens[screenID].frame
                    window.setFrame(targetFrame, display: true, animate: false)
                    window.alphaValue = 0.6  // Semi-transparent.
                    window.level = .screenSaver // Ensure it appears on top.
                    print("Overlay window for display \(screenID + 1) on \(screens[screenID].localizedName)")
                } else {
                    print("No screen available for index \(screenID)")
                }
            }
        })
    }
}
