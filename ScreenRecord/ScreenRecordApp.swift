//
//  ScreenRecordApp.swift
//  ScreenRecord
//
//  Created by Furqan Ali on 3/24/25.
//

import SwiftUI

/* @main
//struct ScreenRecordApp: App {
//    var body: some Scene {
//        WindowGroup {
//            ContentView()
//                .frame(minWidth: 480, minHeight: 300)
//        }
//        .windowStyle(.hiddenTitleBar)
//        .windowResizability(.contentSize)
//    }
//}  */



@main
struct ScreenRecorderApp: App {
    @State private var permissionsGranted = false
    
    var body: some Scene {
        WindowGroup {
            ZStack {
                if permissionsGranted {
                    ContentView()
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
        
        // Secondary window scene with an identifier "SecondWindow"
        WindowGroup("Select Display", id: "SecondWindow") {
            // Pass a fresh view model for the second window.
            SelectDisplayView(viewModel: SelectDisplayViewModel())
        }
    }
}
