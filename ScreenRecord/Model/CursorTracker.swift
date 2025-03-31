////
////  CursorTracker.swift
////  ScreenRecord
////
////  Created by Furqan Ali on 3/26/25.
////
//
//////  original working
//
//
//import Foundation
//import AppKit
//
///// Polling-based cursor tracker that captures mouse position and writes to CSV
//class PollingCursorTracker {
//    // Configuration
//    private let fps: Int
//    private var interval: TimeInterval {
//        return 1.0 / Double(fps)
//    }
//    
//    // Tracking state
//    private var isTracking = false
//    private var trackingStartTimeMs: Int64 = 0
//    private var trackingEndTimeMs: Int64 = 0
//    private var pollingTask: Task<Void, Never>?
//    private var pollCount = 0
//    
//    // CSV batching
//    private var dataBatch: [String] = []
//    private var batchTimer: Timer?
//    private let batchInterval: TimeInterval = 5.0
//    private let batchSize = 150
//    
//    // Cursor state
//    private var lastKnownLocation: NSPoint = .zero
//    
//    // CSV file handling
//    private var csvFileURL: URL?
//    private var csvFileHandle: FileHandle?
//    private var hasWrittenHeader = false
//    
//    // Screen and video info
//    private var displayID: CGDirectDisplayID = 0
//    private var screenWidth: Int = 0
//    private var screenHeight: Int = 0
//    private var videoWidth: Int = 0
//    private var videoHeight: Int = 0
//    
//    init(fps: Int = 30) {
//        self.fps = fps
//    }
//    
//    func startTracking(videoWidth: Int = 0, videoHeight: Int = 0) {
//        guard !isTracking else { return }
//        
//        pollCount = 0
//        dataBatch.removeAll()
//        hasWrittenHeader = false
//        
//        let mainDisplay = NSScreen.main
//        displayID = CGMainDisplayID()
//        screenWidth = Int(mainDisplay?.frame.width ?? 0)
//        screenHeight = Int(mainDisplay?.frame.height ?? 0)
//        
//        self.videoWidth = videoWidth > 0 ? videoWidth : screenWidth
//        self.videoHeight = videoHeight > 0 ? videoHeight : screenHeight
//        
//        trackingStartTimeMs = Int64(Date().timeIntervalSince1970 * 1000)
//        lastKnownLocation = NSEvent.mouseLocation
//        
//        createCSVFile()
//        
//        DispatchQueue.main.async { [weak self] in
//            self?.batchTimer = Timer.scheduledTimer(withTimeInterval: self?.batchInterval ?? 5.0, repeats: true) { [weak self] _ in
//                self?.writeBatchToCSV()
//            }
//        }
//        
//        pollingTask = Task(priority: .background) { [weak self] in
//            guard let self = self else { return }
//            
//            while !Task.isCancelled {
//                await self.pollCursorPosition()
//                try? await Task.sleep(nanoseconds: UInt64(self.interval * 1_000_000_000))
//            }
//        }
//        
//        isTracking = true
//    }
//    
//    func stopTracking() {
//        guard isTracking else { return }
//        
//        trackingEndTimeMs = Int64(Date().timeIntervalSince1970 * 1000)
//        
//        pollingTask?.cancel()
//        pollingTask = nil
//        
//        batchTimer?.invalidate()
//        batchTimer = nil
//        
//        writeBatchToCSV()
//        writeEndTimeAndDuration()
//        closeCSVFile()
//        
//        isTracking = false
//    }
//    
//    private func pollCursorPosition() async {
//        let (location, cursorInfo) = await MainActor.run {
//            let location = NSEvent.mouseLocation
//            
//            let currentCursor = NSCursor.currentSystem
//            let cursorType = identifyCursorType(currentCursor ?? NSCursor.current)
//            let isMoving = isCursorMoving(location)
//            let pressedButtons = NSEvent.pressedMouseButtons
//            
//            return (location, (cursorType, isMoving, pressedButtons))
//        }
//        
//        let currentTimeMs = Int64(Date().timeIntervalSince1970 * 1000)
//        let elapsedTimeMs = currentTimeMs - trackingStartTimeMs
//        
//        let screenHeight = await MainActor.run {
//            return NSScreen.main?.frame.height ?? 0
//        }
//        let adjustedY = screenHeight - location.y
//        
//        pollCount += 1
//        
//        addDataToBatch(
//            x: Int(location.x),
//            y: Int(adjustedY),
//            timestampMs: elapsedTimeMs,
//            buttons: cursorInfo.2,
//            cursorType: cursorInfo.0,
//            isMoving: cursorInfo.1
//        )
//        
//        if dataBatch.count >= batchSize {
//            await MainActor.run {
//                writeBatchToCSV()
//            }
//        }
//    }
//    
//    private func isCursorMoving(_ currentLocation: NSPoint) -> Bool {
//        let dx = abs(currentLocation.x - lastKnownLocation.x)
//        let dy = abs(currentLocation.y - lastKnownLocation.y)
//        
//        if dx < 2.1 && dy < 2.1 {
//            return false
//        }
//        
//        lastKnownLocation = currentLocation
//        return true
//    }
//    
//    private func identifyCursorType(_ cursor: NSCursor) -> String {
//        let image = cursor.image
//        let hotSpot = cursor.hotSpot
//        
//        switch (Int(image.size.width), Int(image.size.height), hotSpot.x, hotSpot.y) {
//        case (17, 23, 4.0, 4.0):
//            return "arrow"
//        case (9, 18, 4.0, 9.0):
//            return "ibeam"
//        case (32, 32, 13.0, 8.0):
//            return "pointing_hand"
//        case (24, 24, 12.0, 12.0):
//            return "resize_horizontal"
//        case (32, 32, 16.0, 16.0):
//            return "grab"
//        case (20, 20, 9.0, 9.0):
//            return "resize_all"
//        case (24, 24, 11.0, 11.0):
//            return "crosshair"
//        case (18, 18, 9.0, 9.0):
//            return "crosshair_cell_type"
//        case (28, 40, 5.0, 5.0):
//            return "copy_generic"
//        case (20, 20, 8.0, 7.0):
//            return "zoom"
//        default:
//            return "arrow"
//        }
//    }
//    
//    private func addDataToBatch(x: Int, y: Int, timestampMs: Int64, buttons: Int, cursorType: String, isMoving: Bool) {
//        // Just the dynamic data for regular rows
//        let dataRow = "\(x),\(y),\(timestampMs),\(buttons),\(cursorType),\(isMoving ? 1 : 0)"
//        dataBatch.append(dataRow)
//    }
//    
//    private func createCSVFile() {
//        guard let downloadsDirectory = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first else { return }
//        
//        let dateFormatter = DateFormatter()
//        dateFormatter.dateFormat = "yyyy-MM-dd-HH-mm-ss"
//        let dateString = dateFormatter.string(from: Date())
//        
//        let fileName = "CursorTracking-\(dateString).csv"
//        csvFileURL = downloadsDirectory.appendingPathComponent(fileName)
//        
//        guard let fileURL = csvFileURL else { return }
//        
//        do {
//            // Create file with the full header
//            let header = "display_id,start_time,end_time,duration,cursor_frame_rate,video_frame_rate,video_width,video_height,screen_x_width,screen_y_height,x,y,timestamp,clicks,cursor_type,cursor_moving\n"
//            try header.write(to: fileURL, atomically: true, encoding: .utf8)
//            
//            // Open file for appending
//            csvFileHandle = try FileHandle(forWritingTo: fileURL)
//            csvFileHandle?.seekToEndOfFile()
//            
//            // Write the first row with static data
//            let staticData = "\(displayID),\(trackingStartTimeMs),,,\(fps),60,\(videoWidth),\(videoHeight),\(screenWidth),\(screenHeight),,,,,,\n"
//            if let data = staticData.data(using: .utf8) {
//                csvFileHandle?.write(data)
//            }
//            
//            hasWrittenHeader = true
//        } catch {
//            print("Error creating CSV file: \(error)")
//        }
//    }
//    
//    private func writeBatchToCSV() {
//        guard let fileHandle = csvFileHandle, !dataBatch.isEmpty else { return }
//        
//        // Write only the dynamic data columns, leaving the static columns empty
//        let rows = dataBatch.map { ",,,,,,,,,," + $0 }
//        let batchData = rows.joined(separator: "\n") + "\n"
//        
//        if let data = batchData.data(using: .utf8) {
//            fileHandle.write(data)
//        }
//        
//        dataBatch.removeAll()
//    }
//    
//    private func writeEndTimeAndDuration() {
//        guard let fileURL = csvFileURL else { return }
//        
//        // We need to close the file handle first
//        try? csvFileHandle?.close()
//        csvFileHandle = nil
//        
//        do {
//            // Read the entire file
//            let fileContents = try String(contentsOf: fileURL, encoding: .utf8)
//            var lines = fileContents.components(separatedBy: "\n")
//            
//            // Update the first data row (line index 1, after the header)
//            if lines.count > 1 {
//                // Parse the first data row
//                var fields = lines[1].components(separatedBy: ",")
//                
//                // Update end time and duration fields (indices 2 and 3)
//                if fields.count > 3 {
//                    let durationMs = trackingEndTimeMs - trackingStartTimeMs
//                    fields[2] = "\(trackingEndTimeMs)"
//                    fields[3] = "\(durationMs)"
//                    
//                    // Rejoin and replace the line
//                    lines[1] = fields.joined(separator: ",")
//                    
//                    // Write back the entire file
//                    let updatedContents = lines.joined(separator: "\n")
//                    try updatedContents.write(to: fileURL, atomically: true, encoding: .utf8)
//                }
//            }
//        } catch {
//            print("Error updating end time in CSV: \(error)")
//        }
//    }
//    
//    private func closeCSVFile() {
//        guard let fileHandle = csvFileHandle else { return }
//        
//        do {
//            try fileHandle.close()
//        } catch {
//            print("Error closing CSV file: \(error)")
//        }
//        
//        csvFileHandle = nil
//    }
//    
//    deinit {
//        if isTracking {
//            stopTracking()
//        }
//    }
//}




//
//  CursorTracker.swift
//  ScreenRecord
//
//  Created by Furqan Ali on 3/26/25.
//

////  test working



import Foundation
import AppKit

/// Combined cursor and keyboard tracker that captures input data and writes to CSV
class PollingCursorAndKeyboardTracker {
    // MARK: - Properties
    
    // Configuration
    private let fps: Int
    private var interval: TimeInterval {
        return 1.0 / Double(fps)
    }
    
    // Tracking state
    private var isTracking = false
    private var trackingStartTimeMs: Int64 = 0
    private var trackingEndTimeMs: Int64 = 0
    private var cursorPollingTask: Task<Void, Never>?
    private var keyboardTrackingTask: Task<Void, Never>?
    private var pollCount = 0
    
    // Input tracking settings
    private var isKeyboardTrackingEnabled = true
    
    // CSV batching
    private var dataBatch: [String] = []
    private var batchTimer: Timer?
    private let batchInterval: TimeInterval = 5.0
    private let batchSize = 150
    
    // Input state
    private var lastKnownLocation: NSPoint = .zero
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    
    // CSV file handling
    private var csvFileURL: URL?
    private var csvFileHandle: FileHandle?
    private var hasWrittenHeader = false
    
    // Screen and video info
    private var displayID: CGDirectDisplayID = 0
    private var screenWidth: Int = 0
    private var screenHeight: Int = 0
    private var videoWidth: Int = 0
    private var videoHeight: Int = 0
    
    // MARK: - Initialization
    
    init(fps: Int = 30, trackKeyboard: Bool = true) {
        self.fps = fps
        self.isKeyboardTrackingEnabled = trackKeyboard
    }
    
    // MARK: - Public Methods
    
    /// Start tracking cursor position and keyboard events
    func startTracking(videoWidth: Int = 0, videoHeight: Int = 0) {
        guard !isTracking else { return }
        
        pollCount = 0
        dataBatch.removeAll()
        hasWrittenHeader = false
        
        let mainDisplay = NSScreen.main
        displayID = CGMainDisplayID()
        screenWidth = Int(mainDisplay?.frame.width ?? 0)
        screenHeight = Int(mainDisplay?.frame.height ?? 0)
        
        self.videoWidth = videoWidth > 0 ? videoWidth : screenWidth
        self.videoHeight = videoHeight > 0 ? videoHeight : screenHeight
        
        trackingStartTimeMs = Int64(Date().timeIntervalSince1970 * 1000)
        lastKnownLocation = NSEvent.mouseLocation
        
        createCSVFile()
        
        DispatchQueue.main.async { [weak self] in
            self?.batchTimer = Timer.scheduledTimer(withTimeInterval: self?.batchInterval ?? 5.0, repeats: true) { [weak self] _ in
                self?.writeBatchToCSV()
            }
        }
        
        // Start cursor tracking in a background task
        cursorPollingTask = Task(priority: .background) { [weak self] in
            guard let self = self else { return }
            
            while !Task.isCancelled {
                await self.pollCursorPosition()
                try? await Task.sleep(nanoseconds: UInt64(self.interval * 1_000_000_000))
            }
        }
        
        // Start keyboard tracking if enabled
        if isKeyboardTrackingEnabled {
            startKeyboardTracking()
        }
        
        isTracking = true
    }
    
    /// Stop tracking cursor position and keyboard events
    func stopTracking() {
        guard isTracking else { return }
        
        trackingEndTimeMs = Int64(Date().timeIntervalSince1970 * 1000)
        
        cursorPollingTask?.cancel()
        cursorPollingTask = nil
        
        stopKeyboardTracking()
        
        batchTimer?.invalidate()
        batchTimer = nil
        
        writeBatchToCSV()
        updateEndTimeAndDuration()
        closeCSVFile()
        
        isTracking = false
    }
    
    // MARK: - Cursor Tracking
    
    /// Poll cursor position at regular intervals
    private func pollCursorPosition() async {
        // Get cursor position and additional info on the main thread
        let (location, cursorInfo) = await MainActor.run {
            let location = NSEvent.mouseLocation
            
            let currentCursor = NSCursor.current
            let cursorType = identifyCursorType(currentCursor)
            let isMoving = isCursorMoving(location)
            let pressedButtons = NSEvent.pressedMouseButtons
            
            return (location, (cursorType, isMoving, pressedButtons))
        }
        
        let currentTimeMs = Int64(Date().timeIntervalSince1970 * 1000)
        let elapsedTimeMs = currentTimeMs - trackingStartTimeMs
        
        let screenHeight = await MainActor.run {
            return NSScreen.main?.frame.height ?? 0
        }
        let adjustedY = screenHeight - location.y
        
        pollCount += 1
        
        // Add cursor data to batch (with empty keyboard fields)
        addCursorDataToBatch(
            x: Int(location.x),
            y: Int(adjustedY),
            timestampMs: elapsedTimeMs,
            buttons: cursorInfo.2,
            cursorType: cursorInfo.0,
            isMoving: cursorInfo.1
        )
        
        if dataBatch.count >= batchSize {
            await MainActor.run {
                writeBatchToCSV()
            }
        }
    }
    
    private func isCursorMoving(_ currentLocation: NSPoint) -> Bool {
        let dx = abs(currentLocation.x - lastKnownLocation.x)
        let dy = abs(currentLocation.y - lastKnownLocation.y)
        
        if dx < 2.1 && dy < 2.1 {
            return false
        }
        
        lastKnownLocation = currentLocation
        return true
    }
    
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
    
    // MARK: - Keyboard Tracking
    
    /// Start monitoring keyboard events
    private func startKeyboardTracking() {
        keyboardTrackingTask = Task(priority: .background) { [weak self] in
            guard let self = self else { return }
            
            // Create event tap on background thread
            await self.setupKeyboardEventTap()
            
            // Keep the task alive until cancelled
            while !Task.isCancelled {
                // Sleep to avoid busy-waiting
                try? await Task.sleep(nanoseconds: 100_000_000) // 100ms
            }
        }
    }
    
    /// Stop monitoring keyboard events
    private func stopKeyboardTracking() {
        keyboardTrackingTask?.cancel()
        keyboardTrackingTask = nil
        
        if let eventTap = eventTap {
            CGEvent.tapEnable(tap: eventTap, enable: false)
            
            if let runLoopSource = runLoopSource {
                CFRunLoopRemoveSource(CFRunLoopGetCurrent(), runLoopSource, .commonModes)
                self.runLoopSource = nil
            }
            
            self.eventTap = nil
        }
    }
    
    /// Set up the keyboard event tap
    private func setupKeyboardEventTap() async {
        await MainActor.run {
            // Define which events to listen for (key down and key up)
            let eventMask = (1 << CGEventType.keyDown.rawValue) | (1 << CGEventType.keyUp.rawValue)
            
            // Create a context object (self) for the callback
            let selfPointer = Unmanaged.passUnretained(self).toOpaque()
            
            // Create the event tap
            guard let eventTap = CGEvent.tapCreate(
                tap: .cgSessionEventTap,
                place: .headInsertEventTap,
                options: .defaultTap,
                eventsOfInterest: CGEventMask(eventMask),
                callback: { proxy, type, event, refcon in
                    guard let refcon = refcon else { return Unmanaged.passUnretained(event) }
                    
                    // Get the tracker instance
                    let tracker = Unmanaged<PollingCursorAndKeyboardTracker>.fromOpaque(refcon).takeUnretainedValue()
                    
                    // Handle the keyboard event
                    if type == .keyDown || type == .keyUp {
                        tracker.handleKeyboardEvent(event: event, isKeyDown: type == .keyDown)
                    }
                    
                    // Pass the event through
                    return Unmanaged.passUnretained(event)
                },
                userInfo: selfPointer
            ) else {
                print("Failed to create keyboard event tap")
                return
            }
            
            self.eventTap = eventTap
            
            // Create a run loop source
            if let runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, eventTap, 0) {
                self.runLoopSource = runLoopSource
                
                // Add source to current run loop
                CFRunLoopAddSource(CFRunLoopGetCurrent(), runLoopSource, .commonModes)
                
                // Enable the tap
                CGEvent.tapEnable(tap: eventTap, enable: true)
            }
        }
    }
    
    /// Handle keyboard events
    private func handleKeyboardEvent(event: CGEvent, isKeyDown: Bool) {
        // Calculate timestamp
        let currentTimeMs = Int64(Date().timeIntervalSince1970 * 1000)
        let elapsedTimeMs = currentTimeMs - trackingStartTimeMs
        
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
        if flags.contains(.maskShift) { modifiers.append("Shift ") }
        if flags.contains(.maskControl) { modifiers.append("Control ") }
        if flags.contains(.maskAlternate) { modifiers.append("Option ") }
        if flags.contains(.maskCommand) { modifiers.append("Command ") }
        if flags.contains(.maskSecondaryFn) { modifiers.append("Fn ") }
        if flags.contains(.maskNumericPad) { modifiers.append("NumPad ") }
        if flags.contains(.maskHelp) { modifiers.append("Help ") }
        
        // Add keyboard data to batch (with empty cursor fields)
        addKeyboardDataToBatch(
            timestampMs: elapsedTimeMs,
            keyState: isKeyDown ? "pressed" : "released",
            keyCode: Int(keyCode),
            character: character,
            modifiers: modifiers.joined()
        )
        
        // Check if batch needs to be written
        if dataBatch.count >= batchSize {
            DispatchQueue.main.async { [weak self] in
                self?.writeBatchToCSV()
            }
        }
    }
    
    // MARK: - Data Management
    
    private func addCursorDataToBatch(x: Int, y: Int, timestampMs: Int64, buttons: Int, cursorType: String, isMoving: Bool) {
        // Data format: x,y,timestamp,clicks,cursor_type,cursor_moving,key_state,key_code,character,modifiers
        let dataRow = "\(x),\(y),\(timestampMs),\(buttons),\(cursorType),\(isMoving ? 1 : 0),,,,"
        dataBatch.append(dataRow)
    }
    
    private func addKeyboardDataToBatch(timestampMs: Int64, keyState: String, keyCode: Int, character: String, modifiers: String) {
        // Data format: x,y,timestamp,clicks,cursor_type,cursor_moving,key_state,key_code,character,modifiers
        // Leave cursor fields empty for keyboard events
        let dataRow = ",,\(timestampMs),,,,\(keyState),\(keyCode),\(character.replacingOccurrences(of: ",", with: " ")),\(modifiers)"
        dataBatch.append(dataRow)
    }
    
    // MARK: - CSV File Handling
    
    private func createCSVFile() {
        guard let downloadsDirectory = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first else { return }
        
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd-HH-mm-ss"
        let dateString = dateFormatter.string(from: Date())
        
        let fileName = "InputTracking-\(dateString).csv"
        csvFileURL = downloadsDirectory.appendingPathComponent(fileName)
        
        guard let fileURL = csvFileURL else { return }
        
        do {
            // Create CSV header with both cursor and keyboard columns
            let header = "display_id,start_time,end_time,duration,cursor_frame_rate,video_frame_rate,video_width,video_height,screen_x_width,screen_y_height,x,y,timestamp,clicks,cursor_type,cursor_moving,key_state,key_code,character,modifiers\n"
            try header.write(to: fileURL, atomically: true, encoding: .utf8)
            
            // Open file for appending
            csvFileHandle = try FileHandle(forWritingTo: fileURL)
            csvFileHandle?.seekToEndOfFile()
            
            // Write the first row with static data
            let staticData = "\(displayID),\(trackingStartTimeMs),,,\(fps),60,\(videoWidth),\(videoHeight),\(screenWidth),\(screenHeight),,,,,,,,,,\n"
            if let data = staticData.data(using: .utf8) {
                csvFileHandle?.write(data)
            }
            
            hasWrittenHeader = true
        } catch {
            print("Error creating CSV file: \(error)")
        }
    }
    
    private func writeBatchToCSV() {
        guard let fileHandle = csvFileHandle, !dataBatch.isEmpty else { return }
        
        // Write rows with empty fields for the static columns
        let rows = dataBatch.map { ",,,,,,,,,," + $0 }
        let batchData = rows.joined(separator: "\n") + "\n"
        
        if let data = batchData.data(using: .utf8) {
            fileHandle.write(data)
        }
        
        dataBatch.removeAll()
    }
    
    private func updateEndTimeAndDuration() {
        guard let fileURL = csvFileURL else { return }
        
        // Close the file handle first
        try? csvFileHandle?.close()
        csvFileHandle = nil
        
        do {
            // Read the entire file
            let fileContents = try String(contentsOf: fileURL, encoding: .utf8)
            var lines = fileContents.components(separatedBy: "\n")
            
            // Update the first data row (line index 1, after the header)
            if lines.count > 1 {
                // Parse the first data row
                var fields = lines[1].components(separatedBy: ",")
                
                // Update end time and duration fields (indices 2 and 3)
                if fields.count > 3 {
                    let durationMs = trackingEndTimeMs - trackingStartTimeMs
                    fields[2] = "\(trackingEndTimeMs)"
                    fields[3] = "\(durationMs)"
                    
                    // Rejoin and replace the line
                    lines[1] = fields.joined(separator: ",")
                    
                    // Write back the entire file
                    let updatedContents = lines.joined(separator: "\n")
                    try updatedContents.write(to: fileURL, atomically: true, encoding: .utf8)
                }
            }
        } catch {
            print("Error updating end time in CSV: \(error)")
        }
    }
    
    private func closeCSVFile() {
        guard let fileHandle = csvFileHandle else { return }
        
        do {
            try fileHandle.close()
        } catch {
            print("Error closing CSV file: \(error)")
        }
        
        csvFileHandle = nil
    }
    
    deinit {
        if isTracking {
            stopTracking()
        }
        
        // Release event tap if still active
        if let eventTap = eventTap {
            CGEvent.tapEnable(tap: eventTap, enable: false)
            
            if let runLoopSource = runLoopSource {
                CFRunLoopRemoveSource(CFRunLoopGetCurrent(), runLoopSource, .commonModes)
            }
        }
        
        // Clear all references
        eventTap = nil
        runLoopSource = nil
    }
}
