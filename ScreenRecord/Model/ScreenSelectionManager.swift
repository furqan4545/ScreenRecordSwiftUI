//
//  ScreenSelectionManager.swift
//  ScreenRecord
//
//  Created by Furqan Ali on 4/13/25.
//
// Manages area selection state across the app - ensuring only one selection at a time
//


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
    
    // Event publisher to notify overlays to close (optional, if you want to use property observation)
    @Published var shouldCloseAllOverlays: Bool = false
    
    // MARK: - Public Methods
    
    func setAreaSelection(_ area: SelectionArea) {
        selectedArea = area
        isSelectionConfirmed = false
    }
    
    func updateAreaSelection(_ area: SelectionArea) {
        if let current = selectedArea, current.screenID == area.screenID {
            selectedArea = area
        } else {
            setAreaSelection(area)
        }
    }
    
    func clearAreaSelection() {
        selectedArea = nil
        isSelectionConfirmed = false
    }
    
    func confirmAreaSelection() {
        guard selectedArea != nil else { return }
        isSelectionConfirmed = true
    }
    
    func startDrawingOnScreen(_ screenID: Int) {
        if let existingSelection = selectedArea, existingSelection.screenID != screenID {
            selectedArea = nil
        }
        isSelectionInProgress = true
    }
    
    func startAreaSelection() {
        isSelectionInProgress = true
        // Not clearing selectedArea here so users can continue from a previous selection if desired.
    }
    
    func registerOverlay(screenID: Int) {
        activeOverlays.insert(screenID)
    }
    
    func unregisterOverlay(screenID: Int) {
        activeOverlays.remove(screenID)
        if activeOverlays.isEmpty {
            isSelectionInProgress = false
            shouldCloseAllOverlays = false
        }
    }
    
    // Update closeAllOverlays() to post a notification that the overlay windows can observe.
    func closeAllOverlays() {
        // Post a notification so that overlay windows close themselves.
        NotificationCenter.default.post(name: Notification.Name("CloseAllOverlays"), object: nil)
        
        // Reset selection state
        isSelectionInProgress = false
        activeOverlays.removeAll()
        
        // Clear the saved selection to avoid it being used on subsequent overlay creation.
        clearAreaSelection()
    }
    
    func getAbsoluteSelectionRect() -> CGRect? {
        guard let selection = selectedArea else { return nil }
        
        let screens = NSScreen.screens
        guard screens.indices.contains(selection.screenID) else { return nil }
        
        let screen = screens[selection.screenID]
        let screenFrame = screen.frame
        
        return CGRect(
            x: screenFrame.origin.x + selection.rect.origin.x,
            y: screenFrame.origin.y + selection.rect.origin.y,
            width: selection.rect.width,
            height: selection.rect.height
        )
    }
    
    func hasActiveSelection(screenID: Int) -> Bool {
        return selectedArea?.screenID == screenID
    }
}
