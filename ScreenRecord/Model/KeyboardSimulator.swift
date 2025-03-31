//
//  KeyboardSimulator.swift
//  ScreenRecord
//
//  Created by Furqan Ali on 3/26/25.
//

import Foundation
import Cocoa

// Helper to simulate keyboard events to trigger accessibility permissions
class KeyboardSimulator {
    static func simulateKeyPress() {
        // Create a string via keyboard simulation to trigger the permission dialog
        let source = CGEventSource(stateID: .hidSystemState)
        
        // Simulate pressing and releasing the 'H' key
        if let keyDownH = CGEvent(keyboardEventSource: source, virtualKey: 0x04, keyDown: true) {
            keyDownH.post(tap: .cghidEventTap)
        }
        if let keyUpH = CGEvent(keyboardEventSource: source, virtualKey: 0x04, keyDown: false) {
            keyUpH.post(tap: .cghidEventTap)
        }
    }
}
