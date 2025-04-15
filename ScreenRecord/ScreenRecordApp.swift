//
//  ScreenRecordApp.swift
//  ScreenRecord
//
//  Created by Furqan Ali on 3/24/25.
//
//

import SwiftUI

@main
struct ScreenRecorderApp: App {
    @State private var permissionsGranted = false
    @State private var showDisplayOverlays = false
    
    // Declare the StateObjects without an initial value.
    @StateObject private var screenSelectionManager: ScreenSelectionManager
    @StateObject private var recorderViewModel: ScreenRecorderViewModel
    
    init() {
        // Create local instances.
        let selectionManager = ScreenSelectionManager()
        let recorderVM = ScreenRecorderViewModel(selectionResetter: selectionManager)
        
        // Assign the local instances to the StateObject wrappers.
        _screenSelectionManager = StateObject(wrappedValue: selectionManager)
        _recorderViewModel = StateObject(wrappedValue: recorderVM)
    }

    

    var body: some Scene {
        WindowGroup {
            ZStack {
                if permissionsGranted {
                    ContentView()
                        .environmentObject(screenSelectionManager)
                        .environmentObject(recorderViewModel)
                } else {
                    PermissionsView(permissionsGranted: $permissionsGranted)
                }
            }
            .onAppear {
                // Check if permissions were previously granted
                permissionsGranted = UserDefaults.standard.bool(forKey: "permissionsGranted")
            }
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
        .commands {
            CommandMenu("Developer") {
                Button("Panic Exit") {
                    NSApp.terminate(nil)
                }
                .keyboardShortcut(.init("P", modifiers: [.command, .shift]))
            }
        }
        .windowLevel(.floating)
//        .modifier(WindowLevelModifier())  // for older versions less than MacOS 15
        
        // Register the dynamic window scene.
        dynamicDisplayScene
        
        // New floating stop button scene.
        floatingStopButtonScene
        
    }
}


extension ScreenRecorderApp {
    @SceneBuilder
    var dynamicDisplayScene: some Scene {
        // The dynamic window group receives an Int (screen index)
        WindowGroup(id: "dynamic-display", for: Int.self) { $screenID in
            if let screenID = screenID {
                SelectDisplayView(screenID: screenID)
                    .environmentObject(screenSelectionManager)
                    .environmentObject(recorderViewModel) // <-- Add this line!
                    .onAppear {
                        // Register this overlay
                        screenSelectionManager.registerOverlay(screenID: screenID)
                    }
                    .onDisappear {
                        // Unregister when closed
                        screenSelectionManager.unregisterOverlay(screenID: screenID)
                    }
            }
        }
        // Add window configuration for overlays if needed (e.g., borderless, specific level)
        // .windowStyle(.plain) // Example
        // .windowLevel(.floating) // Example
    }
    
    // New window scene for the floating stop button.
    @SceneBuilder
        var floatingStopButtonScene: some Scene {
            WindowGroup("Stop Button", id: "stopButton") {
                StopButtonWindowView() // View handles its own background/style
                    .environmentObject(screenSelectionManager)
                    .environmentObject(recorderViewModel)
                    // --- MAKE SURE THERE ARE NO .background() MODIFIERS HERE ---
            }
            .windowStyle(.hiddenTitleBar)
            .windowResizability(.contentSize)
            .windowLevel(.floating)
//            .defaultSize(width: boxSize, height: boxSize) // Use constant or derive
    }
    // Helper constant matching the view (or pass size via environment/preference)
//    private var boxSize: CGFloat { 70 }
}

