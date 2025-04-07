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
    @ObservedObject var viewModel: SelectDisplayViewModel
    @State private var nsWindow: NSWindow?

    var body: some View {
        VStack(spacing: 20) {
            Text("This is the second view")
                .font(.title)
            
            // Your custom close button.
            Button("Close") {
                nsWindow?.close()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
        // Use WindowAccessor to capture the underlying NSWindow and then configure it.
        .background(WindowAccessor { window in
            if let window = window, window != self.nsWindow {
                self.nsWindow = window

                // Remove standard window chrome.
                window.styleMask = [.borderless]
                
                // Set the window to cover the entire main screen.
                if let screenFrame = NSScreen.main?.frame {
                    window.setFrame(screenFrame, display: true, animate: false)
                }
                
                // Make the window semi-transparent.
                window.alphaValue = 0.8
                
                // Set the window level high enough to cover the menu bar and dock.
                window.level = NSWindow.Level.screenSaver

                print("Window set to full screen floating with transparency")
            }
        })
    }
}
