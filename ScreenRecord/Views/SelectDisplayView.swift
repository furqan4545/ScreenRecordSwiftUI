////
////  SelectDisplayView.swift
////  SelectDisplayView
////
////  Created by Furqan Ali on 4/1/25.
////
////


import SwiftUI
import AppKit

struct SelectDisplayView: View {
    let screenID: Int
    @State private var nsWindow: NSWindow?
    @State private var escapeMonitor: Any?
    
    @EnvironmentObject var screenSelectionManager: ScreenSelectionManager
    
    private var screenSize: CGSize {
        let screens = NSScreen.screens
        guard screens.indices.contains(screenID) else { return .zero }
        let frame = screens[screenID].frame
        return CGSize(width: frame.width, height: frame.height)
    }
    
    var body: some View {
        AreaSelectionView(screenID: screenID)
            .frame(width: screenSize.width, height: screenSize.height)
            .onEscapeKeyPress {
                // This will be called when ESC is pressed
                screenSelectionManager.closeAllOverlays()
            }
            .onAppear {
                screenSelectionManager.registerOverlay(screenID: screenID)
                
                // Listen for the "CloseAllOverlays" notification to close this overlay window.
                NotificationCenter.default.addObserver(forName: Notification.Name("CloseAllOverlays"),
                                                       object: nil,
                                                       queue: .main) { _ in
                    self.nsWindow?.close()
                }
            }
            .onDisappear {
                screenSelectionManager.unregisterOverlay(screenID: screenID)
            }
            .background(WindowAccessor { window in
                if let window = window, window != self.nsWindow {
                    self.nsWindow = window
                    let screens = NSScreen.screens
                    if screens.indices.contains(screenID) {
                        let targetFrame = screens[screenID].frame
                        window.styleMask = [.borderless]
                        window.level = .screenSaver
                        window.setFrame(targetFrame, display: true, animate: false)
                        window.isOpaque = false
                        window.backgroundColor = .clear
                        window.alphaValue = 1.0
                        window.hasShadow = false
                        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
                        
                        print("Overlay window for display \(screenID + 1) on \(screens[screenID].localizedName)")
                    } else {
                        print("No screen available for index \(screenID)")
                    }
                }
            })
    }
    
    // Setup a global event monitor for the ESC key
    private func setupEscapeKeyMonitor() {
        // Create a global event monitor for the Escape key
        escapeMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { event in
            // Only handle ESC key and only when we have active overlays
            if event.keyCode == 53 && !screenSelectionManager.activeOverlays.isEmpty {
                DispatchQueue.main.async {
                    screenSelectionManager.closeAllOverlays()
                }
            }
        }
    }
    
    // Clean up the event monitor
    private func removeEscapeKeyMonitor() {
        if let monitor = escapeMonitor {
            NSEvent.removeMonitor(monitor)
            escapeMonitor = nil
        }
    }
}

