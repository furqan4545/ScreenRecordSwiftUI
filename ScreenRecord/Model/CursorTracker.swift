//
//  CursorTracker.swift
//  ScreenRecord
//
//  Created by Furqan Ali on 3/26/25.
//

////  original working
//
//import Foundation
//import AppKit
//
///// Polling-based cursor tracker that captures mouse position using Swift concurrency
//class PollingCursorTracker {
//    // MARK: - Properties
//    
//    // Configuration
//    private let fps: Int
//    private var interval: TimeInterval {
//        return 1.0 / Double(fps)
//    }
//    
//    // Tracking state
//    private var isTracking = false
//    private var trackingStartTime: Date?
//    private var pollCount = 0
//    private var clickCount = 0
//    
//    // Task management
//    private var pollingTask: Task<Void, Never>?
//    private var clickMonitor: Any?
//    
//    // MARK: - Initialization
//    
//    init(fps: Int = 30) {
//        self.fps = fps
//    }
//    
//    // MARK: - Public Methods
//    
//    /// Start tracking cursor position at the configured frame rate
//    func startTracking() {
//        guard !isTracking else { return }
//        
//        // Reset counters
//        pollCount = 0
//        clickCount = 0
//        
//        // Record start time
//        trackingStartTime = Date()
//        print("Starting cursor tracking at \(trackingStartTime!) with \(fps) fps")
//        
//        // Start background polling task
//        pollingTask = Task(priority: .background) { [weak self] in
//            guard let self = self else { return }
//            
//            // Keep polling until task is cancelled
//            while !Task.isCancelled {
//                // Poll cursor position
//                await self.pollCursorPosition()
//                
//                // Wait for next interval
//                try? await Task.sleep(nanoseconds: UInt64(self.interval * 1_000_000_000))
//            }
//        }
//        
//        // Set up click monitor
//        clickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
//            self?.handleMouseClick(event)
//        }
//        
//        isTracking = true
//    }
//    
//    /// Stop tracking cursor position
//    func stopTracking() {
//        guard isTracking else { return }
//        
//        // Cancel polling task
//        pollingTask?.cancel()
//        pollingTask = nil
//        
//        // Remove click monitor
//        if let clickMonitor = clickMonitor {
//            NSEvent.removeMonitor(clickMonitor)
//            self.clickMonitor = nil
//        }
//        
//        // Calculate tracking duration
//        if let startTime = trackingStartTime {
//            let duration = Date().timeIntervalSince(startTime)
//            print("Stopped cursor tracking. Duration: \(String(format: "%.2f", duration)) seconds")
//            print("Recorded \(pollCount) position samples and \(clickCount) clicks")
//        }
//        
//        isTracking = false
//        trackingStartTime = nil
//    }
//    
//    // MARK: - Private Methods
//    
//    /// Poll cursor position at regular intervals
//    private func pollCursorPosition() async {
//        // This must run on the main thread to access NSEvent.mouseLocation
//        let position = await MainActor.run {
//            return NSEvent.mouseLocation
//        }
//        
//        // Get elapsed time since tracking started
//        guard let startTime = trackingStartTime else { return }
//        let elapsedTime = Date().timeIntervalSince(startTime)
//        
//        // Convert screen coordinates
//        let screenHeight = await MainActor.run {
//            return NSScreen.main?.frame.height ?? 0
//        }
//        let adjustedY = screenHeight - position.y
//        
//        pollCount += 1
//        
//        // Log every position - at 30fps this could be a lot, so consider limiting in production
//        print("[Position @ \(String(format: "%.3f", elapsedTime))s] x: \(Int(position.x)), y: \(Int(adjustedY))")
//    }
//    
//    /// Handle mouse click events
//    private func handleMouseClick(_ event: NSEvent) {
//        let position = NSEvent.mouseLocation
//        
//        // Get elapsed time since tracking started
//        guard let startTime = trackingStartTime else { return }
//        let elapsedTime = Date().timeIntervalSince(startTime)
//        
//        // Convert screen coordinates
//        let screenHeight = NSScreen.main?.frame.height ?? 0
//        let adjustedY = screenHeight - position.y
//        
//        // Determine click type
//        let clickType = event.type == .leftMouseDown ? "Left Click" : "Right Click"
//        
//        clickCount += 1
//        
//        print("[\(clickType) @ \(String(format: "%.3f", elapsedTime))s] x: \(Int(position.x)), y: \(Int(adjustedY))")
//    }
//    
//    // Clean up resources
//    deinit {
//        stopTracking()
//    }
//}
//
//


//////////////////////////  test
///
///




import Foundation
import AppKit

/// Polling-based cursor tracker that captures mouse position and writes to CSV
class PollingCursorTracker {
    // Configuration
    private let fps: Int
    private var interval: TimeInterval {
        return 1.0 / Double(fps)
    }
    
    // Tracking state
    private var isTracking = false
    private var trackingStartTimeMs: Int64 = 0
    private var trackingEndTimeMs: Int64 = 0
    private var pollingTask: Task<Void, Never>?
    private var pollCount = 0
    
    // CSV batching
    private var dataBatch: [String] = []
    private var batchTimer: Timer?
    private let batchInterval: TimeInterval = 5.0
    private let batchSize = 150
    
    // Cursor state
    private var lastKnownLocation: NSPoint = .zero
    
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
    
    init(fps: Int = 30) {
        self.fps = fps
    }
    
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
        
        pollingTask = Task(priority: .background) { [weak self] in
            guard let self = self else { return }
            
            while !Task.isCancelled {
                await self.pollCursorPosition()
                try? await Task.sleep(nanoseconds: UInt64(self.interval * 1_000_000_000))
            }
        }
        
        isTracking = true
    }
    
    func stopTracking() {
        guard isTracking else { return }
        
        trackingEndTimeMs = Int64(Date().timeIntervalSince1970 * 1000)
        
        pollingTask?.cancel()
        pollingTask = nil
        
        batchTimer?.invalidate()
        batchTimer = nil
        
        writeBatchToCSV()
        writeEndTimeAndDuration()
        closeCSVFile()
        
        isTracking = false
    }
    
    private func pollCursorPosition() async {
        let (location, cursorInfo) = await MainActor.run {
            let location = NSEvent.mouseLocation
            
            let currentCursor = NSCursor.currentSystem
            let cursorType = identifyCursorType(currentCursor ?? NSCursor.current)
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
        
        addDataToBatch(
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
    
    private func addDataToBatch(x: Int, y: Int, timestampMs: Int64, buttons: Int, cursorType: String, isMoving: Bool) {
        // Just the dynamic data for regular rows
        let dataRow = "\(x),\(y),\(timestampMs),\(buttons),\(cursorType),\(isMoving ? 1 : 0)"
        dataBatch.append(dataRow)
    }
    
    private func createCSVFile() {
        guard let downloadsDirectory = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first else { return }
        
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd-HH-mm-ss"
        let dateString = dateFormatter.string(from: Date())
        
        let fileName = "CursorTracking-\(dateString).csv"
        csvFileURL = downloadsDirectory.appendingPathComponent(fileName)
        
        guard let fileURL = csvFileURL else { return }
        
        do {
            // Create file with the full header
            let header = "display_id,start_time,end_time,duration,cursor_frame_rate,video_frame_rate,video_width,video_height,screen_x_width,screen_y_height,x,y,timestamp,clicks,cursor_type,cursor_moving\n"
            try header.write(to: fileURL, atomically: true, encoding: .utf8)
            
            // Open file for appending
            csvFileHandle = try FileHandle(forWritingTo: fileURL)
            csvFileHandle?.seekToEndOfFile()
            
            // Write the first row with static data
            let staticData = "\(displayID),\(trackingStartTimeMs),,,\(fps),60,\(videoWidth),\(videoHeight),\(screenWidth),\(screenHeight),,,,,,\n"
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
        
        // Write only the dynamic data columns, leaving the static columns empty
        let rows = dataBatch.map { ",,,,,,,,,," + $0 }
        let batchData = rows.joined(separator: "\n") + "\n"
        
        if let data = batchData.data(using: .utf8) {
            fileHandle.write(data)
        }
        
        dataBatch.removeAll()
    }
    
    private func writeEndTimeAndDuration() {
        guard let fileURL = csvFileURL else { return }
        
        // We need to close the file handle first
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
    }
}
