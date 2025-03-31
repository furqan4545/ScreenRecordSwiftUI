//
//  CursorTrackingV2.swift
//  ScreenRecord
//
//  Created by Furqan Ali on 3/30/25.
//
///////// / without polling
//import Foundation
//import AppKit
//
///// Event-based cursor tracker that captures mouse movement and clicks
//class EventBasedCursorTracker {
//    // MARK: - Properties
//    
//    // Tracking state
//    private var isTracking = false
//    private var trackingStartTime: Date?
//    
//    // Event monitors
//    private var moveMonitor: Any?
//    private var clickMonitor: Any?
//    
//    // Counters for debugging
//    private var moveEventCount = 0
//    private var clickEventCount = 0
//    
//    // MARK: - Public Methods
//    
//    /// Start tracking cursor movements and clicks
//    func startTracking() {
//        guard !isTracking else { return }
//        
//        // Reset counters
//        moveEventCount = 0
//        clickEventCount = 0
//        
//        // Record start time
//        trackingStartTime = Date()
//        print("Starting cursor tracking at \(trackingStartTime!)")
//        
//        // Set up mouse movement monitor
//        moveMonitor = NSEvent.addGlobalMonitorForEvents(matching: .mouseMoved) { [weak self] event in
//            self?.handleMouseMove(event)
//        }
//        
//        // Set up mouse click monitor
//        clickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
//            self?.handleMouseClick(event)
//        }
//        
//        isTracking = true
//    }
//    
//    /// Stop tracking cursor movements and clicks
//    func stopTracking() {
//        guard isTracking else { return }
//        
//        // Remove event monitors
//        if let moveMonitor = moveMonitor {
//            NSEvent.removeMonitor(moveMonitor)
//            self.moveMonitor = nil
//        }
//        
//        if let clickMonitor = clickMonitor {
//            NSEvent.removeMonitor(clickMonitor)
//            self.clickMonitor = nil
//        }
//        
//        // Calculate tracking duration
//        if let startTime = trackingStartTime {
//            let duration = Date().timeIntervalSince(startTime)
//            print("Stopped cursor tracking. Duration: \(String(format: "%.2f", duration)) seconds")
//            print("Tracked \(moveEventCount) move events and \(clickEventCount) click events")
//        }
//        
//        isTracking = false
//        trackingStartTime = nil
//    }
//    
//    // MARK: - Private Methods
//    
//    /// Handle mouse movement events
//    private func handleMouseMove(_ event: NSEvent) {
//        let location = event.locationInWindow
//        let globalLocation = NSEvent.mouseLocation
//        
//        // Get elapsed time since tracking started
//        guard let startTime = trackingStartTime else { return }
//        let elapsedTime = Date().timeIntervalSince(startTime)
//        
//        // Convert screen coordinates (optional)
//        let screenHeight = NSScreen.main?.frame.height ?? 0
//        let adjustedY = screenHeight - globalLocation.y
//        
//        moveEventCount += 1
//        
//        // Only log every 10th move event to avoid console flooding
//        if moveEventCount % 10 == 0 {
//            print("[Move @ \(String(format: "%.3f", elapsedTime))s] x: \(Int(globalLocation.x)), y: \(Int(adjustedY))")
//        }
//    }
//    
//    /// Handle mouse click events
//    private func handleMouseClick(_ event: NSEvent) {
//        let location = NSEvent.mouseLocation
//        
//        // Get elapsed time since tracking started
//        guard let startTime = trackingStartTime else { return }
//        let elapsedTime = Date().timeIntervalSince(startTime)
//        
//        // Convert screen coordinates (optional)
//        let screenHeight = NSScreen.main?.frame.height ?? 0
//        let adjustedY = screenHeight - location.y
//        
//        // Determine click type
//        let clickType = event.type == .leftMouseDown ? "Left Click" : "Right Click"
//        
//        clickEventCount += 1
//        
//        print("[\(clickType) @ \(String(format: "%.3f", elapsedTime))s] x: \(Int(location.x)), y: \(Int(adjustedY))")
//    }
//    
//    // Clean up resources
//    deinit {
//        stopTracking()
//    }
//}


////////////////// with polling ///////////


import Foundation
import AppKit

/// Polling-based cursor tracker that captures mouse position using Swift concurrency
class PollingCursorTracker {
    // MARK: - Properties
    
    // Configuration
    private let fps: Int
    private var interval: TimeInterval {
        return 1.0 / Double(fps)
    }
    
    // Tracking state
    private var isTracking = false
    private var trackingStartTime: Date?
    private var pollCount = 0
    private var clickCount = 0
    
    // Task management
    private var pollingTask: Task<Void, Never>?
    private var clickMonitor: Any?
    
    // MARK: - Initialization
    
    init(fps: Int = 30) {
        self.fps = fps
    }
    
    // MARK: - Public Methods
    
    /// Start tracking cursor position at the configured frame rate
    func startTracking() {
        guard !isTracking else { return }
        
        // Reset counters
        pollCount = 0
        clickCount = 0
        
        // Record start time
        trackingStartTime = Date()
        print("Starting cursor tracking at \(trackingStartTime!) with \(fps) fps")
        
        // Start background polling task
        pollingTask = Task(priority: .background) { [weak self] in
            guard let self = self else { return }
            
            // Keep polling until task is cancelled
            while !Task.isCancelled {
                // Poll cursor position
                await self.pollCursorPosition()
                
                // Wait for next interval
                try? await Task.sleep(nanoseconds: UInt64(self.interval * 1_000_000_000))
            }
        }
        
        // Set up click monitor
        clickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
            self?.handleMouseClick(event)
        }
        
        isTracking = true
    }
    
    /// Stop tracking cursor position
    func stopTracking() {
        guard isTracking else { return }
        
        // Cancel polling task
        pollingTask?.cancel()
        pollingTask = nil
        
        // Remove click monitor
        if let clickMonitor = clickMonitor {
            NSEvent.removeMonitor(clickMonitor)
            self.clickMonitor = nil
        }
        
        // Calculate tracking duration
        if let startTime = trackingStartTime {
            let duration = Date().timeIntervalSince(startTime)
            print("Stopped cursor tracking. Duration: \(String(format: "%.2f", duration)) seconds")
            print("Recorded \(pollCount) position samples and \(clickCount) clicks")
        }
        
        isTracking = false
        trackingStartTime = nil
    }
    
    // MARK: - Private Methods
    
    /// Poll cursor position at regular intervals
    private func pollCursorPosition() async {
        // This must run on the main thread to access NSEvent.mouseLocation
        let position = await MainActor.run {
            return NSEvent.mouseLocation
        }
        
        // Get elapsed time since tracking started
        guard let startTime = trackingStartTime else { return }
        let elapsedTime = Date().timeIntervalSince(startTime)
        
        // Convert screen coordinates
        let screenHeight = await MainActor.run {
            return NSScreen.main?.frame.height ?? 0
        }
        let adjustedY = screenHeight - position.y
        
        pollCount += 1
        
        // Log every position - at 30fps this could be a lot, so consider limiting in production
        print("[Position @ \(String(format: "%.3f", elapsedTime))s] x: \(Int(position.x)), y: \(Int(adjustedY))")
    }
    
    /// Handle mouse click events
    private func handleMouseClick(_ event: NSEvent) {
        let position = NSEvent.mouseLocation
        
        // Get elapsed time since tracking started
        guard let startTime = trackingStartTime else { return }
        let elapsedTime = Date().timeIntervalSince(startTime)
        
        // Convert screen coordinates
        let screenHeight = NSScreen.main?.frame.height ?? 0
        let adjustedY = screenHeight - position.y
        
        // Determine click type
        let clickType = event.type == .leftMouseDown ? "Left Click" : "Right Click"
        
        clickCount += 1
        
        print("[\(clickType) @ \(String(format: "%.3f", elapsedTime))s] x: \(Int(position.x)), y: \(Int(adjustedY))")
    }
    
    // Clean up resources
    deinit {
        stopTracking()
    }
}
