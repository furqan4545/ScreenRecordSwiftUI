//
//  KeyHandlerView.swift
//  ScreenRecord
//
//  Created by Furqan Ali on 4/14/25.
//
//

import SwiftUI
import AppKit

// This class handles local keyboard events for a window
class LocalKeyEventMonitor {
    private var monitor: Any?
    private let mask: NSEvent.EventTypeMask
    private let handler: (NSEvent) -> NSEvent?
    
    init(mask: NSEvent.EventTypeMask, handler: @escaping (NSEvent) -> NSEvent?) {
        self.mask = mask
        self.handler = handler
    }
    
    func start() {
        monitor = NSEvent.addLocalMonitorForEvents(matching: mask, handler: handler)
    }
    
    func stop() {
        if let monitor = monitor {
            NSEvent.removeMonitor(monitor)
            self.monitor = nil
        }
    }
    
    deinit {
        stop()
    }
}

// A SwiftUI modifier that adds ESC key handling to any view
struct EscKeyPressHandler: ViewModifier {
    let action: () -> Void
    @State private var keyMonitor: LocalKeyEventMonitor?
    
    func body(content: Content) -> some View {
        content
            .onAppear {
                // Initialize and start the monitor
                keyMonitor = LocalKeyEventMonitor(mask: .keyDown) { event in
                    if event.keyCode == 53 { // 53 is the key code for ESC
                        action()
                        return nil // Consume the event
                    }
                    return event // Pass the event through
                }
                keyMonitor?.start()
            }
            .onDisappear {
                // Clean up the monitor
                keyMonitor?.stop()
            }
    }
}

// Extension to make it easy to add the ESC handler to any view
extension View {
    func onEscapeKeyPress(perform action: @escaping () -> Void) -> some View {
        self.modifier(EscKeyPressHandler(action: action))
    }
}

// Usage example:
// someView.onEscapeKeyPress { closeAllOverlays() }
