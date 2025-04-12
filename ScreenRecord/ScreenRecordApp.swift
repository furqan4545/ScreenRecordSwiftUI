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
    
    
//    @StateObject private var screenRecorder = ScreenRecorderV2()
    
    var body: some Scene {
        WindowGroup {
            ZStack {
                if permissionsGranted {
                    ContentView()
//                        .environmentObject(screenRecorder)
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
        
        // Register the dynamic window scene.
        dynamicDisplayScene
        // register window selector.
//        windowSelectorScene
        
    }
}


extension ScreenRecorderApp {
    @SceneBuilder
    var dynamicDisplayScene: some Scene {
        // The dynamic window group receives an Int (screen index)
        WindowGroup(id: "dynamic-display", for: Int.self) { $screenID in
            if let screenID = screenID {
                SelectDisplayView(screenID: screenID)
            }
        }
    }
}
