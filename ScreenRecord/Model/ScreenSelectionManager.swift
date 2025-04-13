//
//  ScreenSelectionManager.swift
//  ScreenRecord
//
//  Created by Furqan Ali on 4/13/25.
//
// Manages area selection state across the app
//
//import SwiftUI
//import Combine
//
//class ScreenSelectionManager: ObservableObject {
//    // The currently selected area if any
//    @Published var selectedArea: SelectionArea?
//    
//    // Selection state
//    @Published var isSelectionConfirmed: Bool = false
//    @Published var isSelectionInProgress: Bool = false
//    
//    // Track which displays have active selection overlays
//    @Published var activeOverlays: Set<Int> = []
//    
//    // Public methods
//    
//    // Set a new area selection
//    func setAreaSelection(_ area: SelectionArea) {
//        selectedArea = area
//        isSelectionConfirmed = false
//    }
//    
//    // Clear the current selection
//    func clearAreaSelection() {
//        selectedArea = nil
//        isSelectionConfirmed = false
//    }
//    
//    // Confirm the current selection
//    func confirmAreaSelection() {
//        guard selectedArea != nil else { return }
//        isSelectionConfirmed = true
//        
//        // Close all overlays
//        closeAllOverlays()
//    }
//    
//    // Start the area selection process
//    func startAreaSelection() {
//        isSelectionInProgress = true
//        isSelectionConfirmed = false
//        selectedArea = nil
//        
//        // This will be called before opening the overlays
//    }
//    
//    // Register an active overlay
//    func registerOverlay(screenID: Int) {
//        activeOverlays.insert(screenID)
//    }
//    
//    // Unregister an overlay when closed
//    func unregisterOverlay(screenID: Int) {
//        activeOverlays.remove(screenID)
//        
//        // If all overlays are closed and no selection was confirmed, reset
//        if activeOverlays.isEmpty && !isSelectionConfirmed {
//            isSelectionInProgress = false
//        }
//    }
//    
//    // Close all active overlays
//    func closeAllOverlays() {
//        // This is a signal to close overlays - the actual closing
//        // happens in the app via environment messages or similar
//        isSelectionInProgress = false
//        activeOverlays.removeAll()
//    }
//    
//    // Get absolute coordinates for the selection
//    func getAbsoluteSelectionRect() -> CGRect? {
//        guard let selection = selectedArea else { return nil }
//        
//        // Get screen coordinates
//        let screens = NSScreen.screens
//        guard screens.indices.contains(selection.screenID) else { return nil }
//        
//        let screen = screens[selection.screenID]
//        let screenFrame = screen.frame
//        
//        // Transform relative coordinates to absolute
//        return CGRect(
//            x: screenFrame.origin.x + selection.rect.origin.x,
//            y: screenFrame.origin.y + selection.rect.origin.y,
//            width: selection.rect.width,
//            height: selection.rect.height
//        )
//    }
//}


// ScreenSelectionManager.swift
// Manages area selection state across the app - ensuring only one selection at a time


// ScreenSelectionManager.swift
// Enhanced manager for syncing selections across screens

import SwiftUI
import Combine
import AppKit

class ScreenSelectionManager: ObservableObject {
    // The currently selected area if any - only one selection allowed
    @Published var selectedArea: SelectionArea?
    
    // Selection state
    @Published var isSelectionConfirmed: Bool = false
    @Published var isSelectionInProgress: Bool = false
    
    // Track which displays have active selection overlays
    @Published var activeOverlays: Set<Int> = []
    
    // Public methods
    
    // Set a new area selection - this clears any previous selection
    func setAreaSelection(_ area: SelectionArea) {
        // Set the new selection - publishing this change will notify all views
        selectedArea = area
        isSelectionConfirmed = false
    }
    
    // Update an existing selection without triggering resets
    func updateAreaSelection(_ area: SelectionArea) {
        // Only update if it's the same screen that's already selected
        if let current = selectedArea, current.screenID == area.screenID {
            selectedArea = area
        } else {
            // Otherwise treat as a new selection
            setAreaSelection(area)
        }
    }
    
    // Clear the current selection
    func clearAreaSelection() {
        selectedArea = nil
        isSelectionConfirmed = false
    }
    
    // Confirm the current selection
    func confirmAreaSelection() {
        guard selectedArea != nil else { return }
        isSelectionConfirmed = true
        
        // Close all overlays
        closeAllOverlays()
    }
    
    // Start the area selection process
    func startAreaSelection() {
        isSelectionInProgress = true
        
        // Don't clear the selectedArea here so users can continue from previous selection
    }
    
    // Register an active overlay
    func registerOverlay(screenID: Int) {
        activeOverlays.insert(screenID)
    }
    
    // Unregister an overlay when closed
    func unregisterOverlay(screenID: Int) {
        activeOverlays.remove(screenID)
        
        // If all overlays are closed and no selection was confirmed, reset
        if activeOverlays.isEmpty && !isSelectionConfirmed {
            isSelectionInProgress = false
        }
    }
    
    // Close all active overlays
    func closeAllOverlays() {
        // This is a signal to close overlays - the actual closing
        // happens in the app via environment messages or similar
        isSelectionInProgress = false
        activeOverlays.removeAll()
    }
    
    // Get absolute coordinates for the selection
    func getAbsoluteSelectionRect() -> CGRect? {
        guard let selection = selectedArea else { return nil }
        
        // Get screen coordinates
        let screens = NSScreen.screens
        guard screens.indices.contains(selection.screenID) else { return nil }
        
        let screen = screens[selection.screenID]
        let screenFrame = screen.frame
        
        // Transform relative coordinates to absolute
        return CGRect(
            x: screenFrame.origin.x + selection.rect.origin.x,
            y: screenFrame.origin.y + selection.rect.origin.y,
            width: selection.rect.width,
            height: selection.rect.height
        )
    }
    
    // Helper to check if a screen has an active selection
    func hasActiveSelection(screenID: Int) -> Bool {
        return selectedArea?.screenID == screenID
    }
    
    // Method to immediately notify that drawing is starting on a specific screen
    func startDrawingOnScreen(_ screenID: Int) {
        // If we already have a selection on a different screen, clear it now
        if let existingSelection = selectedArea, existingSelection.screenID != screenID {
            // Clear the previous selection - this will notify all views
            selectedArea = nil
        }
        
        // Mark that we're starting to draw on this screen
        // This will be used when an actual selection is made
        isSelectionInProgress = true
    }
}
