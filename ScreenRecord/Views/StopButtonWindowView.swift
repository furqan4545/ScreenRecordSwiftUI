//
//  StopButtonWindowView.swift
//  ScreenRecord
//
//  Created by Furqan Ali on 4/15/25.
//
//
//

import SwiftUI

// WindowAccessor helper struct remains the same

struct StopButtonWindowView: View {
    @EnvironmentObject var viewModel: ScreenRecorderViewModel
    @EnvironmentObject var screenSelectionManager: ScreenSelectionManager
    @Environment(\.dismiss) private var dismiss
    @State private var windowRef: NSWindow?

    // --- Define the NEW dark gradient for the border ---
    let borderGradient = LinearGradient(
        gradient: Gradient(colors: [
            Color.indigo.opacity(0.8), // Dark Purple/Indigo side
            Color.blue.opacity(0.8)    // Dark Blue side
        ]),
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    // Define the size for the control box
    let boxSize: CGFloat = 75 // Adjusted size slightly

    // Define border width
    let borderWidth: CGFloat = 4.5
    // --- CONTROL CORNER RADIUS ---
    let cornerRadius: CGFloat = 30 // <<<< ADD THIS (Adjust value as needed)

    var body: some View {
        Button {
            print("Stop button tapped!")
            viewModel.stopRecording()
            screenSelectionManager.closeAllOverlays()
            dismiss()
        } label: {
            Image(systemName: "stop.fill")
                .resizable()
                .scaledToFit()
                .foregroundColor(.red.opacity(0.9)) // Red icon for stop
                .frame(width: boxSize * 0.5, height: boxSize * 0.5) // Size relative to box
        }
        .buttonStyle(.plain)
        .frame(width: boxSize, height: boxSize) // Set the overall frame size

        // --- NO background material modifier here ---
        // The background will be transparent by default

        // --- Apply Square Gradient Border Overlay ---
        .overlay {
            // <<< USE RoundedRectangle HERE >>>
            RoundedRectangle(cornerRadius: cornerRadius)
                .stroke(borderGradient, lineWidth: borderWidth)
        }

        // --- Subtle Shadow for the whole control (Button + Border) ---
        // Apply shadow *after* the overlay so it affects the border too
         .shadow(color: .black.opacity(0.35), radius: 5, x: 0, y: 3)

        // --- Attach WindowAccessor (Crucial for Transparency & Dragging) ---
        .background(
            WindowAccessor { window in
                DispatchQueue.main.async {
                    guard let window = window else { return }
                    if window != self.windowRef {
                        self.windowRef = window
                        window.isOpaque = false            // MUST be false for transparency
                        window.backgroundColor = .clear   // MUST be clear
                        window.level = .floating
                        window.styleMask = [.borderless]
                        window.hasShadow = false          // Use view's shadow only
                        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle, .stationary]
                        window.isMovableByWindowBackground = true
                        window.orderFrontRegardless()
                    }
                }
            }
        )
    }
}

#Preview {
    // Preview with a contrasting background to see the border and transparency
    ZStack {
        LinearGradient(gradient: Gradient(colors: [.gray, .black]), startPoint: .top, endPoint: .bottom)
           .ignoresSafeArea()

        StopButtonWindowView()
            .environmentObject(ScreenRecorderViewModel())
            .environmentObject(ScreenSelectionManager())
    }
}
