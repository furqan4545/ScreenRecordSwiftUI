//
//  InputTracker.swift
//  ScreenRecord
//
//  Created by Furqan Ali on 3/26/25.
//


import Foundation
import Cocoa

class InputTracker {
    // MARK: - Enums
    enum TrackingState {
        case idle
        case tracking
        case error(Error)
    }
    
    // MARK: - Published Properties
    @Published var state: TrackingState = .idle
    @Published var currentCursorPosition: CGPoint = .zero
    @Published var outputURL: URL?
    
    // MARK: - Private Properties
    private let trackingQueue = DispatchQueue(label: "com.screenrecord.inputtracking", qos: .userInitiated)
    private var trackingWorkItem: DispatchWorkItem?
    
    private var startTime: TimeInterval = 0
    private var lastKnownLocation: NSPoint = .zero
    private var currentCursorType: String = "unknown"
    
    private var displayID: CGDirectDisplayID = 0
    private var width: Int = 0
    private var height: Int = 0
    private var originalWidth: Int = 0
    private var originalHeight: Int = 0
    private var videoFrameRate: Int = 60
    
    private var cursorPositions: [[String: Any]] = []
    private var keyboardData: [[String: Any]] = []
    
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var runLoop: CFRunLoop?
    
    // MARK: - Initialization
    init() {
        setupDisplayInfo()
    }
    
    // MARK: - Public Methods
    
    /// Start tracking user input (cursor and keyboard)
    func startTracking() {
        guard case .idle = state else { return }
        
        // Reset tracking data
        cursorPositions.removeAll()
        keyboardData.removeAll()
        startTime = Date().timeIntervalSince1970
        lastKnownLocation = NSEvent.mouseLocation
        state = .tracking
        
        // Create a work item for tracking
        let workItem = DispatchWorkItem { [weak self] in
            guard let self = self else { return }
            self.runInputTracking()
        }
        
        // Store the work item and start tracking on background queue
        trackingWorkItem = workItem
        trackingQueue.async(execute: workItem)
    }
    
    /// Stop tracking user input
    func stopTracking() {
        guard case .tracking = state else { return }
        
        // Cancel the work item if it's still running
        trackingWorkItem?.cancel()
        trackingWorkItem = nil
        
        // Disable the event tap from the main thread
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            
            if let eventTap = self.eventTap {
                CGEvent.tapEnable(tap: eventTap, enable: false)
            }
            
            // Save the data and update state
            self.saveInputData()
            self.state = .idle
        }
    }
    
    // MARK: - Private Methods
    
    /// Set up display information
    private func setupDisplayInfo() {
        if let screen = NSScreen.main {
            width = Int(screen.frame.width)
            height = Int(screen.frame.height)
            originalWidth = width
            originalHeight = height
            
            // Get display ID
            if let screenNumber = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber {
                displayID = screenNumber.uint32Value
            }
        }
    }
    
    /// Main method that runs input tracking
    private func runInputTracking() {
        // Request accessibility permissions if needed
        if !AXIsProcessTrusted() {
            let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
            AXIsProcessTrustedWithOptions(options as CFDictionary)
            
            DispatchQueue.main.async { [weak self] in
                self?.state = .error(NSError(domain: "InputTracker", code: 1, userInfo: [NSLocalizedDescriptionKey: "Accessibility permissions required for input tracking"]))
            }
            return
        }
        
        // Set up keyboard tracking
        setupKeyboardTracking()
        
        // Set up cursor tracking timer
        let cursorTimer = Timer(timeInterval: 1.0/30.0, repeats: true) { [weak self] _ in
            self?.captureCursorPosition()
        }
        
        // Create a run loop for tracking
        runLoop = CFRunLoopGetCurrent()
        
        // Add the cursor timer to the run loop
        RunLoop.current.add(cursorTimer, forMode: .common)
        
        // Keep the run loop running until tracking is stopped
        while !Thread.current.isCancelled,
              case .tracking = state,
              let runLoop = runLoop {
            CFRunLoopRunInMode(.defaultMode, 0.1, false)
        }
        
        // Clean up when the run loop exits
        if let runLoopSource = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetCurrent(), runLoopSource, .commonModes)
        }
    }
    
    /// Set up keyboard event tracking
    private func setupKeyboardTracking() {
        // Create a retained reference to self for the callbacks
        let selfPtr = Unmanaged.passRetained(self).toOpaque()
        
        // Define which events to listen for (key down and key up)
        let eventMask = (1 << CGEventType.keyDown.rawValue) | (1 << CGEventType.keyUp.rawValue)
        
        // Create the event tap
        guard let eventTap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(eventMask),
            callback: { proxy, type, event, refcon in
                guard let refcon = refcon else { return Unmanaged.passUnretained(event) }
                
                // Get the InputTracker instance from refcon
                let tracker = Unmanaged<InputTracker>.fromOpaque(refcon).takeUnretainedValue()
                
                // Handle the keyboard event
                if type == .keyDown || type == .keyUp {
                    tracker.handleKeyboardEvent(event: event, isKeyDown: type == .keyDown)
                }
                
                // Pass the event through
                return Unmanaged.passUnretained(event)
            },
            userInfo: selfPtr
        ) else {
            DispatchQueue.main.async { [weak self] in
                self?.state = .error(NSError(domain: "InputTracker", code: 2, userInfo: [NSLocalizedDescriptionKey: "Failed to create keyboard event tap"]))
            }
            return
        }
        
        // Save the event tap reference
        self.eventTap = eventTap
        
        // Create a run loop source from the event tap
        let runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, eventTap, 0)
        self.runLoopSource = runLoopSource
        
        // Add the source to the current run loop
        CFRunLoopAddSource(CFRunLoopGetCurrent(), runLoopSource, .commonModes)
        
        // Enable the event tap
        CGEvent.tapEnable(tap: eventTap, enable: true)
    }
    
    /// Handle keyboard events
    private func handleKeyboardEvent(event: CGEvent, isKeyDown: Bool) {
        // Extract key information
        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
        
        // Extract Unicode characters
        var actualLength: Int = 0
        var chars = [UniChar](repeating: 0, count: 4)
        event.keyboardGetUnicodeString(
            maxStringLength: 4,
            actualStringLength: &actualLength,
            unicodeString: &chars
        )
        
        // Convert to string
        let character = String(utf16CodeUnits: chars, count: actualLength)
        
        // Extract modifier keys
        let flags = event.flags
        var modifiers: [String] = []
        if flags.contains(.maskShift) { modifiers.append("⇧") }
        if flags.contains(.maskControl) { modifiers.append("⌃") }
        if flags.contains(.maskAlternate) { modifiers.append("⌥") }
        if flags.contains(.maskCommand) { modifiers.append("⌘") }
        
        // Calculate timestamp
        let currentTime = Date().timeIntervalSince1970
        let timestamp = Int((currentTime - startTime) * 1000)
        
        // Record keyboard event with timestamp
        keyboardData.append([
            "key_state": isKeyDown ? "pressed" : "released",
            "key_code": keyCode,
            "character": character,
            "timestamp": timestamp,
            "modifiers": modifiers.joined()
        ])
    }
    
    /// Capture cursor position and information
    private func captureCursorPosition() {
        let timestamp = Int((Date().timeIntervalSince1970 - startTime) * 1000)
        let location = NSEvent.mouseLocation
        
        // Use currentSystem for more accurate cursor type
        guard let cursor = NSCursor.currentSystem else { return }
        
        // Get cursor type and movement status
        let isMoving = isCursorMoving(location)
        let cursorType = identifyCursorType(cursor)
        
        // Track cursor type changes
        if cursorType != currentCursorType {
            currentCursorType = cursorType
        }
        
        // Add to array
        cursorPositions.append([
            "x": Int(location.x),
            "y": Int(location.y),
            "timestamp": timestamp,
            "click": NSEvent.pressedMouseButtons,
            "cursor_type": cursorType,
            "cursor_moving": isMoving ? 1 : 0
        ])
        
        // Update current position for observers
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.currentCursorPosition = CGPoint(x: location.x, y: location.y)
        }
    }
    
    /// Check if cursor is moving
    private func isCursorMoving(_ currentLocation: NSPoint) -> Bool {
        let dx = abs(currentLocation.x - lastKnownLocation.x)
        let dy = abs(currentLocation.y - lastKnownLocation.y)
        
        if dx < 2.1 && dy < 2.1 {
            return false
        }
        
        lastKnownLocation = currentLocation
        return true
    }
    
    /// Identify cursor type
    private func identifyCursorType(_ cursor: NSCursor) -> String {
        let image = cursor.image
        let hotSpot = cursor.hotSpot
        
        switch (Int(image.size.width), Int(image.size.height), hotSpot.x, hotSpot.y) {
        case (17, 23, 4.0, 4.0):
            return "arrow"
        case (9, 18, 4.0, 9.0):
            return "ibeam"
        case (32, 32, 13.0, 8.0):
            return "pointing_hand"
        case (24, 24, 12.0, 12.0):
            return "resize_horizontal"
        case (32, 32, 16.0, 16.0):
            return "grab"
        case (20, 20, 9.0, 9.0):
            return "resize_all"
        case (24, 24, 11.0, 11.0):
            return "crosshair"
        case (18, 18, 9.0, 9.0):
            return "crosshair_cell_type"
        case (28, 40, 5.0, 5.0):
            return "copy_generic"
        case (20, 20, 8.0, 7.0):
            return "zoom"
        default:
            return "arrow"
        }
    }
    
    /// Format data for output
    private var outputData: [String: Any] {
        let currentTimeMs = Int(Date().timeIntervalSince1970 * 1000)
        let startTimeMs = Int(startTime * 1000)
        return [
            "RecordingInfo": [
                "screen": "display_\(displayID)",
                "start_time": startTimeMs,
                "end_time": currentTimeMs,
                "duration": currentTimeMs - startTimeMs,
                "cursor_frame_rate": 30,
                "video_frame_rate": videoFrameRate,
                "global_width": self.width,
                "global_height": self.height,
                "recorded_display_dimension": [
                    "x_width": self.originalWidth,
                    "y_height": self.originalHeight
                ]
            ],
            "recorded_cursor_data": cursorPositions,
            "keyboard_data": keyboardData
        ]
    }
    
    /// Save the input data to a JSON file
    private func saveInputData() {
        do {
            // Convert to JSON data
            let jsonData = try JSONSerialization.data(withJSONObject: outputData, options: .prettyPrinted)
            
            // Create a URL in the Downloads directory
            if let downloadsDirectory = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first {
                let dateFormatter = DateFormatter()
                dateFormatter.dateFormat = "yyyy-MM-dd-HH-mm-ss"
                let dateString = dateFormatter.string(from: Date())
                let url = downloadsDirectory.appendingPathComponent("InputData-\(dateString).json")
                
                try jsonData.write(to: url)
                
                // Update outputURL on main thread
                DispatchQueue.main.async { [weak self] in
                    self?.outputURL = url
                }
                
                print("Input tracking data saved to: \(url.path)")
            }
        } catch {
            print("Error saving input tracking data: \(error.localizedDescription)")
            DispatchQueue.main.async { [weak self] in
                self?.state = .error(error)
            }
        }
    }
    
    // Clean up resources when the object is deallocated
    deinit {
        if case .tracking = state {
            stopTracking()
        }
        
        // Just in case, make sure the event tap is disabled
        if let eventTap = eventTap {
            CGEvent.tapEnable(tap: eventTap, enable: false)
        }
    }
}
