//
//  AreaSelectionView.swift
//  ScreenRecord
//
//  Created by Furqan Ali on 4/13/25.
//
//


import SwiftUI
import Combine

struct SelectionArea {
    var rect: CGRect
    var screenID: Int
}

// Selection interaction state
enum SelectionState {
    case idle
    case drawing
    case moving
    case resizing(Corner)
}

// Corner identifiers for resizing
enum Corner {
    case topLeft, topRight, bottomLeft, bottomRight
    case top, left, bottom, right
}

struct AreaSelectionView: View {
    let screenID: Int
    
    // Selection state
    @State private var selectionStart: CGPoint?
    @State private var currentSelection: CGRect = .zero
    @State private var selectionCompleted: Bool = false
    @State private var selectionState: SelectionState = .idle
    @State private var dragOffset: CGPoint = .zero
    @State private var viewSize: CGSize = .zero
    @State private var showSizeWarning: Bool = false
    
    // Constants
    private let MIN_WIDTH: CGFloat = 300
    private let MIN_HEIGHT: CGFloat = 200
    private let handleSize: CGFloat = 8
    private let halfHandleSize: CGFloat = 4
    
    // Store the completed selection area in the manager
    @EnvironmentObject var screenSelectionManager: ScreenSelectionManager
    
    // Recorder view model from environment
    @EnvironmentObject var recorderViewModel: ScreenRecorderViewModel
    
    // Cancellable for tracking selection changes
    @State private var cancellable: AnyCancellable?
    
    // Environment to access window dismissal
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Save the view size for bounds checking
                Color.clear
                    .preference(key: SizePreferenceKey.self, value: geometry.size)
                    .onPreferenceChange(SizePreferenceKey.self) { size in
                        viewSize = size
                    }
                
                // Canvas overlay: draw a dim black overlay when recording has started,
                // or use blue otherwise. In both cases, carve out the selected region so it remains transparent.
                Canvas { context, size in
                    // Use the shared isRecordingStarted property for the overlay color.
                    let overlayColor: Color = screenSelectionManager.isRecordingStarted
                        ? Color.black.opacity(0.6)
                        : Color(red: 95/255, green: 102/255, blue: 255/255).opacity(0.22)
                    
                    context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(overlayColor))
                    
                    if !currentSelection.isEmpty {
                        // Always clear the selected region so it stays transparent.
                        context.blendMode = .clear
                        context.fill(Path(currentSelection), with: .color(.white))
                        context.blendMode = .normal
                        
                        // Draw border & handles only if not recording.
                        if !screenSelectionManager.isRecordingStarted {
                            context.stroke(Path(currentSelection), with: .color(.white), lineWidth: 2)
                            if selectionCompleted && currentSelection.width >= 20 && currentSelection.height >= 20 {
                                drawHandles(context: context)
                            }
                        }
                    }
                }
                
                // Display dimensions near the selection (only when not recording)
                if !screenSelectionManager.isRecordingStarted && !currentSelection.isEmpty && currentSelection.width > 60 && currentSelection.height > 30 {
                    Text("\(Int(currentSelection.width)) × \(Int(currentSelection.height))")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.white)
                        .padding(4)
                        .background(Color.black.opacity(0.7))
                        .cornerRadius(4)
                        .position(
                            x: currentSelection.midX,
                            y: currentSelection.minY - 20
                        )
                }
                
                // Start Recording button is visible only when not recording.
                if !screenSelectionManager.isRecordingStarted && selectionCompleted && !currentSelection.isEmpty {
                    Button {
                        print("Start Recording requested:")
                        print("Selection Rectangle: \(currentSelection)")
                        print("Screen ID: \(screenID)")
                        
                        if screenID < recorderViewModel.displays.count {
                            let targetDisplay = recorderViewModel.displays[screenID]
                            // Set the recording state immediately (without animation)
                            screenSelectionManager.isRecordingStarted = true
                            
                            recorderViewModel.startAreaRecording(on: targetDisplay, with: currentSelection)
                            
                        } else {
                            print("Invalid screen ID")
                        }
                    } label: {
                        HStack {
                            Image(systemName: "record.circle")
                                .font(.system(size: 18))
                            Text("Start Recording")
                                .fontWeight(.medium)
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(Color.red)
                        .foregroundColor(.white)
                        .cornerRadius(8)
                        .shadow(radius: 3)
                    }
                    .buttonStyle(PlainButtonStyle())
                    .position(x: currentSelection.midX, y: currentSelection.midY)
                }
                
                // Instructions text shown only when not recording.
                if !screenSelectionManager.isRecordingStarted && !selectionCompleted {
                    VStack {
                        Text(currentSelection.isEmpty
                             ? "Click and drag to select area to record"
                             : "Click inside to move, on edges to resize, or outside to reset")
                            .font(.headline)
                            .foregroundColor(.white)
                            .padding()
                            .background(Color.black.opacity(0.6))
                            .cornerRadius(8)
                            .shadow(radius: 2)
                            .padding(.top, 40)
                        Spacer()
                    }
                }
                
                // Bottom control box (Reset / Cancel) shown only when not recording.
                if !screenSelectionManager.isRecordingStarted {
                    VStack {
                        Spacer()
                        HStack(spacing: 20) {
                            if selectionCompleted {
                                Button {
                                    resetSelection()
                                } label: {
                                    Text("Reset")
                                        .fontWeight(.semibold)
                                        .foregroundColor(.black)
                                        .padding(.vertical, 7)
                                        .padding(.horizontal, 24)
                                        .background(Color.yellow)
                                        .cornerRadius(8)
                                }
                                .buttonStyle(PlainButtonStyle())
                            }
                            Button {
                                closeAllOverlayWindows()
                            } label: {
                                Text("Cancel")
                                    .fontWeight(.semibold)
                                    .foregroundColor(.white)
                                    .padding(.vertical, 7)
                                    .padding(.horizontal, 24)
                                    .background(Color.red)
                                    .cornerRadius(8)
                            }
                            .buttonStyle(PlainButtonStyle())
                        }
                        .padding(.vertical, 16)
                        .padding(.horizontal, 20)
                        .frame(height: 55)
                        .background(Color.black.opacity(0.7))
                        .cornerRadius(10)
                        .padding(.bottom, 20)
                    }
                }
                
                // Size warning message
                if showSizeWarning {
                    Text("Selection must be at least 300×200 pixels")
                        .font(.headline)
                        .foregroundColor(.white)
                        .padding()
                        .background(Color.red.opacity(0.8))
                        .cornerRadius(8)
                        .shadow(radius: 3)
                        .transition(.opacity)
                        .position(x: geometry.size.width / 2, y: geometry.size.height / 2)
                        .onAppear {
                            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                                withAnimation { showSizeWarning = false }
                            }
                        }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle()) // Make the entire view respond to gestures.
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in handleDragChange(value) }
                    .onEnded { value in handleDragEnd(value) }
            )
            .onExitCommand { closeAllOverlayWindows() }
            .onAppear {
                updateFromManager()
                cancellable = screenSelectionManager.$selectedArea.sink { area in
                    if let area = area, area.screenID == screenID {
                        currentSelection = area.rect
                        selectionCompleted = true
                    } else {
                        currentSelection = .zero
                        selectionCompleted = false
                    }
                }
            }
            .onDisappear { cancellable?.cancel() }
        }
    }
    
    // Close all overlay windows.
    private func closeAllOverlayWindows() {
        NotificationCenter.default.post(name: Notification.Name("CloseAllOverlays"), object: nil)
        screenSelectionManager.closeAllOverlays()
    }
    
    // Draw resize handles (only used when not recording).
    private func drawHandles(context: GraphicsContext) {
        let handles: [(CGPoint, Corner)] = [
            (CGPoint(x: currentSelection.minX, y: currentSelection.minY), .topLeft),
            (CGPoint(x: currentSelection.midX, y: currentSelection.minY), .top),
            (CGPoint(x: currentSelection.maxX, y: currentSelection.minY), .topRight),
            (CGPoint(x: currentSelection.maxX, y: currentSelection.midY), .right),
            (CGPoint(x: currentSelection.maxX, y: currentSelection.maxY), .bottomRight),
            (CGPoint(x: currentSelection.midX, y: currentSelection.maxY), .bottom),
            (CGPoint(x: currentSelection.minX, y: currentSelection.maxY), .bottomLeft),
            (CGPoint(x: currentSelection.minX, y: currentSelection.midY), .left)
        ]
        
        for (position, _) in handles {
            let handleRect = CGRect(
                x: position.x - halfHandleSize,
                y: position.y - halfHandleSize,
                width: handleSize,
                height: handleSize
            )
            context.fill(Path(ellipseIn: handleRect), with: .color(.white))
            context.stroke(Path(ellipseIn: handleRect), with: .color(.blue), lineWidth: 1.5)
        }
    }
    
    // Handle drag gesture change.
    private func handleDragChange(_ value: DragGesture.Value) {
        switch selectionState {
        case .idle:
            if selectionCompleted {
                if let corner = getCornerForPosition(value.startLocation) {
                    selectionState = .resizing(corner)
                    selectionStart = value.startLocation
                } else if currentSelection.contains(value.startLocation) {
                    selectionState = .moving
                    dragOffset = CGPoint(x: value.startLocation.x - currentSelection.origin.x,
                                         y: value.startLocation.y - currentSelection.origin.y)
                } else {
                    selectionState = .drawing
                    selectionStart = value.startLocation
                    currentSelection = .zero
                    selectionCompleted = false
                    screenSelectionManager.startDrawingOnScreen(screenID)
                }
            } else {
                selectionState = .drawing
                selectionStart = value.startLocation
                currentSelection = .zero
                screenSelectionManager.startDrawingOnScreen(screenID)
            }
        case .drawing:
            guard let start = selectionStart else { return }
            var current = value.location
            current.x = max(0, min(current.x, viewSize.width))
            current.y = max(0, min(current.y, viewSize.height))
            let minX = min(start.x, current.x)
            let minY = min(start.y, current.y)
            let maxX = max(start.x, current.x)
            let maxY = max(start.y, current.y)
            currentSelection = CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
        case .moving:
            var newOrigin = CGPoint(x: value.location.x - dragOffset.x,
                                    y: value.location.y - dragOffset.y)
            newOrigin.x = max(0, min(newOrigin.x, viewSize.width - currentSelection.width))
            newOrigin.y = max(0, min(newOrigin.y, viewSize.height - currentSelection.height))
            currentSelection = CGRect(origin: newOrigin, size: currentSelection.size)
        case .resizing(let corner):
            resize(from: corner, to: value.location)
        }
    }
    
    // Handle drag gesture end.
    private func handleDragEnd(_ value: DragGesture.Value) {
        switch selectionState {
        case .drawing:
            if currentSelection.width >= MIN_WIDTH && currentSelection.height >= MIN_HEIGHT {
                selectionCompleted = true
                saveSelectionToManager()
            } else {
                withAnimation { showSizeWarning = true }
                resetSelection()
            }
        case .moving, .resizing:
            saveSelectionToManager()
        case .idle:
            break
        }
        selectionState = .idle
        selectionStart = nil
    }
    
    // Save the current selection to the manager.
    private func saveSelectionToManager() {
        let area = SelectionArea(rect: currentSelection, screenID: screenID)
        screenSelectionManager.setAreaSelection(area)
    }
    
    // Return the corner for a given point.
    private func getCornerForPosition(_ position: CGPoint) -> Corner? {
        let handleRadius: CGFloat = 10
        if position.distance(to: CGPoint(x: currentSelection.minX, y: currentSelection.minY)) < handleRadius { return .topLeft }
        if position.distance(to: CGPoint(x: currentSelection.maxX, y: currentSelection.minY)) < handleRadius { return .topRight }
        if position.distance(to: CGPoint(x: currentSelection.minX, y: currentSelection.maxY)) < handleRadius { return .bottomLeft }
        if position.distance(to: CGPoint(x: currentSelection.maxX, y: currentSelection.maxY)) < handleRadius { return .bottomRight }
        if abs(position.y - currentSelection.minY) < handleRadius &&
           position.x > currentSelection.minX && position.x < currentSelection.maxX { return .top }
        if abs(position.y - currentSelection.maxY) < handleRadius &&
           position.x > currentSelection.minX && position.x < currentSelection.maxX { return .bottom }
        if abs(position.x - currentSelection.minX) < handleRadius &&
           position.y > currentSelection.minY && position.y < currentSelection.maxY { return .left }
        if abs(position.x - currentSelection.maxX) < handleRadius &&
           position.y > currentSelection.minY && position.y < currentSelection.maxY { return .right }
        return nil
    }
    
    // Resize the selection based on a corner and a new position.
    private func resize(from corner: Corner, to position: CGPoint) {
        var newRect = currentSelection
        let boundedPosition = CGPoint(
            x: max(0, min(position.x, viewSize.width)),
            y: max(0, min(position.y, viewSize.height))
        )
        
        switch corner {
        case .topLeft:
            let width = currentSelection.maxX - boundedPosition.x
            let height = currentSelection.maxY - boundedPosition.y
            if width > 10 && height > 10 {
                newRect = CGRect(x: boundedPosition.x, y: boundedPosition.y, width: width, height: height)
            }
        case .topRight:
            let width = boundedPosition.x - currentSelection.minX
            let height = currentSelection.maxY - boundedPosition.y
            if width > 10 && height > 10 {
                newRect = CGRect(x: currentSelection.minX, y: boundedPosition.y, width: width, height: height)
            }
        case .bottomLeft:
            let width = currentSelection.maxX - boundedPosition.x
            let height = boundedPosition.y - currentSelection.minY
            if width > 10 && height > 10 {
                newRect = CGRect(x: boundedPosition.x, y: currentSelection.minY, width: width, height: height)
            }
        case .bottomRight:
            let width = boundedPosition.x - currentSelection.minX
            let height = boundedPosition.y - currentSelection.minY
            if width > 10 && height > 10 {
                newRect = CGRect(x: currentSelection.minX, y: currentSelection.minY, width: width, height: height)
            }
        case .top:
            let height = currentSelection.maxY - boundedPosition.y
            if height > 10 {
                newRect = CGRect(x: currentSelection.minX, y: boundedPosition.y, width: currentSelection.width, height: height)
            }
        case .left:
            let width = currentSelection.maxX - boundedPosition.x
            if width > 10 {
                newRect = CGRect(x: boundedPosition.x, y: currentSelection.minY, width: width, height: currentSelection.height)
            }
        case .bottom:
            let height = boundedPosition.y - currentSelection.minY
            if height > 10 {
                newRect = CGRect(x: currentSelection.minX, y: currentSelection.minY, width: currentSelection.width, height: height)
            }
        case .right:
            let width = boundedPosition.x - currentSelection.minX
            if width > 10 {
                newRect = CGRect(x: currentSelection.minX, y: currentSelection.minY, width: width, height: currentSelection.height)
            }
        }
        currentSelection = newRect
    }
    
    // Update local state from the manager.
    private func updateFromManager() {
        if let area = screenSelectionManager.selectedArea {
            if area.screenID == screenID {
                currentSelection = area.rect
                selectionCompleted = true
            } else {
                currentSelection = .zero
                selectionCompleted = false
            }
        } else {
            currentSelection = .zero
            selectionCompleted = false
        }
    }
    
    private func resetSelection() {
        selectionStart = nil
        currentSelection = .zero
        selectionCompleted = false
        selectionState = .idle
        
        if let area = screenSelectionManager.selectedArea, area.screenID == screenID {
            screenSelectionManager.clearAreaSelection()
        }
    }
    
    private func confirmSelection() {
        screenSelectionManager.confirmAreaSelection()
        closeAllOverlayWindows()
    }
}

// Helper for getting view size.
struct SizePreferenceKey: PreferenceKey {
    static var defaultValue: CGSize = .zero
    static func reduce(value: inout CGSize, nextValue: () -> CGSize) {
        value = nextValue()
    }
}

// Extension to calculate distance between points.
extension CGPoint {
    func distance(to point: CGPoint) -> CGFloat {
        let dx = point.x - self.x
        let dy = point.y - self.y
        return sqrt(dx * dx + dy * dy)
    }
}
