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
    
    // Create and provide the selection manager
    @StateObject private var screenSelectionManager = ScreenSelectionManager()
    @StateObject private var recorderViewModel = ScreenRecorderViewModel()
    
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
        
        // Register the dynamic window scene.
        dynamicDisplayScene
        
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
    }
}
