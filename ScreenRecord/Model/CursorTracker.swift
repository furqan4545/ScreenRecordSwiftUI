//
//  CursorTracker.swift
//  ScreenRecord
//
//  Created by Furqan Ali on 3/26/25.
//


import Foundation
import Cocoa

class CursorTracker {
    // MARK: - Properties
    private var isTracking = false
    private var trackingTimer: Timer?
    private var trackingQueue = DispatchQueue(label: "com.screenrecord.cursortracking", qos: .userInitiated)
    private var startTime: TimeInterval = 0
    private var lastKnownLocation: NSPoint = .zero
    private var videoFrameRate: Int = 60
    private var width: Int = 0
    private var height: Int = 0
    private var originalWidth: Int = 0
    private var originalHeight: Int = 0
    private var displayID: CGDirectDisplayID = 0
    
    // Array to store cursor positions
    private var cursorPositions: [[String: Any]] = []
    private var keyboardData: [[String: Any]] = []
    
    // Published properties for MVVM pattern
    @Published var isRecording = false
    @Published var currentPosition: CGPoint = .zero
    @Published var outputURL: URL?
    
    // MARK: - Initialization
    init() {
        // Get main display information
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
    
    // MARK: - Public Methods
    
    // Start tracking cursor positions
    func startTracking() {
        guard !isTracking else { return }
        
        isTracking = true
        isRecording = true
        cursorPositions.removeAll()
        keyboardData.removeAll()
        startTime = Date().timeIntervalSince1970
        lastKnownLocation = NSEvent.mouseLocation
        
        // Use a dispatch source timer for more precise timing
        trackingQueue.async { [weak self] in
            guard let self = self else { return }
            
            // Create a timer that fires at 30 fps (approximately every 0.033 seconds)
            let timer = Timer(timeInterval: 1.0/30.0, repeats: true) { [weak self] _ in
                guard let self = self, self.isTracking else { return }
                self.captureCursorPosition()
            }
            
            // Add the timer to the current runloop
            RunLoop.current.add(timer, forMode: .common)
            RunLoop.current.run()
            
            self.trackingTimer = timer
        }
        
        print("Cursor tracking started")
    }
    
    // Stop tracking cursor positions
    func stopTracking() {
        guard isTracking else { return }
        
        isTracking = false
        isRecording = false
        
        // Invalidate the timer
        trackingTimer?.invalidate()
        trackingTimer = nil
        
        // Save cursor positions to file
        saveCursorPositions()
        
        print("Cursor tracking stopped with \(cursorPositions.count) positions recorded")
    }
    
    // MARK: - Private Methods
    
    // Capture the current cursor position
    private func captureCursorPosition() {
        let timestamp = Int((Date().timeIntervalSince1970 - startTime) * 1000)
        let location = NSEvent.mouseLocation
        
        // Get cursor type and movement status
        let isMoving = isCursorMoving(location)
        // Use currentSystem instead of current
        guard let cursor = NSCursor.currentSystem else { return }
        let cursorType = identifyCursorType(cursor)
        
        // Add to array
        self.cursorPositions.append([
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
            self.currentPosition = location
        }
    }
    
    // Check if cursor is moving
    private func isCursorMoving(_ currentLocation: NSPoint) -> Bool {
        let dx = abs(currentLocation.x - lastKnownLocation.x)
        let dy = abs(currentLocation.y - lastKnownLocation.y)
        
        if dx < 2.1 && dy < 2.1 {
            return false
        }
        
        lastKnownLocation = currentLocation
        return true
    }
    
    // Identify cursor type
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
    
    // Create the output data in the required format
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
    
    // Save cursor positions to a file
    private func saveCursorPositions() {
        do {
            // Convert to JSON data
            let jsonData = try JSONSerialization.data(withJSONObject: outputData, options: .prettyPrinted)
            
            // Create a URL in the Downloads directory
            if let downloadsDirectory = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first {
                let dateFormatter = DateFormatter()
                dateFormatter.dateFormat = "yyyy-MM-dd-HH-mm-ss"
                let dateString = dateFormatter.string(from: Date())
                let url = downloadsDirectory.appendingPathComponent("CursorData-\(dateString).json")
                
                try jsonData.write(to: url)
                
                // Update outputURL on main thread
                DispatchQueue.main.async { [weak self] in
                    self?.outputURL = url
                }
                
                print("Cursor data saved to: \(url.path)")
            }
        } catch {
            print("Error saving cursor data: \(error.localizedDescription)")
        }
    }
}
