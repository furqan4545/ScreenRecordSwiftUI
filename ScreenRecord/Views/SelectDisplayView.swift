////
////  SelectDisplayView.swift
////  SelectDisplayView
////
////  Created by Furqan Ali on 4/1/25.
////
////
//
//
//import SwiftUI
//import AppKit
//
//struct SelectDisplayView: View {
//    let screenID: Int
//    @State private var nsWindow: NSWindow?
//
//    var body: some View {
//        VStack(spacing: 20) {
//            Text("Display \(screenID + 1)")
//                .font(.title)
//                .foregroundColor(.white)
//            
//            // Custom close button to close this overlay window.
//            Button("Close") {
//                nsWindow?.close()
//            }
//        }
//        .frame(maxWidth: .infinity, maxHeight: .infinity)
//        .background(WindowAccessor { window in
//            if let window = window, window != self.nsWindow {
//                self.nsWindow = window
//                let screens = NSScreen.screens
//                if screens.indices.contains(screenID) {
//                    // Configure the window:
//                    window.styleMask = [.borderless] // Remove standard chrome.
//                    let targetFrame = screens[screenID].frame
//                    window.setFrame(targetFrame, display: true, animate: false)
//                    window.alphaValue = 0.6  // Semi-transparent.
//                    window.level = .screenSaver // Ensure it appears on top.
//                    print("Overlay window for display \(screenID + 1) on \(screens[screenID].localizedName)")
//                } else {
//                    print("No screen available for index \(screenID)")
//                }
//            }
//        })
//    }
//}


// SelectDisplayView.swift
// Simplified overlay view for area selection on screens


// SelectDisplayView.swift
// Pure SwiftUI overlay for area selection



// SelectDisplayView.swift
// Full screen overlay including menu bar

import SwiftUI
import AppKit

struct SelectDisplayView: View {
    let screenID: Int
    @State private var nsWindow: NSWindow?
    
    // Environment object for managing selections
    @EnvironmentObject var screenSelectionManager: ScreenSelectionManager
    
    // Get the screen size - using full frame including menu bar
    private var screenSize: CGSize {
        let screens = NSScreen.screens
        guard screens.indices.contains(screenID) else { return .zero }
        // Use the full frame including menu bar
        let frame = screens[screenID].frame
        return CGSize(width: frame.width, height: frame.height)
    }
    
    var body: some View {
        // Use our pure SwiftUI area selection view
        AreaSelectionView(screenID: screenID)
            .frame(width: screenSize.width, height: screenSize.height)
            .onAppear {
                // Register this overlay
                screenSelectionManager.registerOverlay(screenID: screenID)
            }
            .onDisappear {
                // Unregister when closed
                screenSelectionManager.unregisterOverlay(screenID: screenID)
            }
            .background(WindowAccessor { window in
                if let window = window, window != self.nsWindow {
                    self.nsWindow = window
                    let screens = NSScreen.screens
                    if screens.indices.contains(screenID) {
                        // Position the window on the correct screen - using FULL frame
                        let targetFrame = screens[screenID].frame
                        
                        // Critical settings for full screen coverage
                        window.styleMask = [.borderless]
                        window.level = .screenSaver
                        
                        // Make window cover the entire screen including menu bar
                        window.setFrame(targetFrame, display: true, animate: false)
                        
                        // Make transparent but not click-through
                        window.isOpaque = false
                        window.backgroundColor = .clear
                        window.hasShadow = false
                        
                        // Set window to appear above menu bar
                        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
                        
                        // Set up ESC key to close window
                        NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
                            if event.keyCode == 53 { // ESC key
                                window.close()
                                return nil
                            }
                            return event
                        }
                        
                        print("Overlay window for display \(screenID + 1) on \(screens[screenID].localizedName)")
                    } else {
                        print("No screen available for index \(screenID)")
                    }
                }
            })
    }
}
