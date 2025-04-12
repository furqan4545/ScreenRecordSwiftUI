////
////  WindowPickerManager.swift
////  WindowPickerManager
////
////  Created by Furqan Ali on 4/8/25.
////
//
//import Foundation
//import ScreenCaptureKit
//import SwiftUI
//
//// This class specifically handles window picking functionality
//class WindowPickerManager: NSObject, ObservableObject, SCContentSharingPickerObserver {
//    // MARK: - Published Properties
//    @Published var isPickerActive: Bool = false
//    @Published var selectedContentFilter: SCContentFilter?
//    
//    // MARK: - Callback
//    var onContentSelected: ((SCContentFilter) -> Void)?
//    // Add a new callback for cancel events
//    var onPickerCancelled: (() -> Void)?
//    
//    // MARK: - Initialization
//    override init() {
//        super.init()
//        setupWindowPicker()
//    }
//    
//    // MARK: - Public Methods
//    func showPicker() {
//        SCContentSharingPicker.shared.isActive = true
//        SCContentSharingPicker.shared.present()
//    }
//    
//    func dismissPicker() {
//        SCContentSharingPicker.shared.isActive = false
//    }
//    
//    // MARK: - Private Methods
//    private func setupWindowPicker() {
//        var pickerConfiguration = SCContentSharingPickerConfiguration()
//        pickerConfiguration.allowedPickerModes = .singleWindow
//        pickerConfiguration.allowsChangingSelectedContent = false
//        
//        SCContentSharingPicker.shared.configuration = pickerConfiguration
//        SCContentSharingPicker.shared.add(self)
//    }
//    
//    // MARK: - SCContentSharingPickerObserver Methods
//    func contentSharingPicker(_ picker: SCContentSharingPicker, didCancelFor stream: SCStream?) {
//        SCContentSharingPicker.shared.isActive = false
//        // Call the cancellation callback
//        onPickerCancelled?()
//    }
//    
//    func contentSharingPicker(_ picker: SCContentSharingPicker, didUpdateWith filter: SCContentFilter, for stream: SCStream?) {
//        // This means the window has been selected
//        SCContentSharingPicker.shared.isActive = false
//        selectedContentFilter = filter
//        onContentSelected?(filter)
//    }
//    
//    func contentSharingPickerStartDidFailWithError(_ error: any Error) {
//        print("Window picker error: \(error.localizedDescription)")
//    }
//}
//




///////////////////////////////////////
///
///

import Foundation
import ScreenCaptureKit
import SwiftUI

class WindowPickerManager: NSObject, ObservableObject, SCContentSharingPickerObserver {
    enum PickerMode {
        case window
        case display
    }
    
    // MARK: - Published Properties
    @Published var isPickerActive: Bool = false
    @Published var selectedContentFilter: SCContentFilter?
    
    // MARK: - Callbacks
    var onContentSelected: ((SCContentFilter) -> Void)?
    var onPickerCancelled: (() -> Void)?
    
    // MARK: - Initialization
    override init() {
        super.init()
        SCContentSharingPicker.shared.add(self)
    }
    
    // MARK: - Public Methods
    func showPicker(mode: PickerMode) {
        // Configure for the appropriate mode
        var pickerConfiguration = SCContentSharingPickerConfiguration()
        
        switch mode {
        case .window:
            pickerConfiguration.allowedPickerModes = .singleWindow
        case .display:
            pickerConfiguration.allowedPickerModes = .singleDisplay
        }
        
        pickerConfiguration.allowsChangingSelectedContent = false
        
        SCContentSharingPicker.shared.configuration = pickerConfiguration
        SCContentSharingPicker.shared.isActive = true
        SCContentSharingPicker.shared.present()
    }
    
    // MARK: - SCContentSharingPickerObserver Methods
    func contentSharingPicker(_ picker: SCContentSharingPicker, didCancelFor stream: SCStream?) {
        SCContentSharingPicker.shared.isActive = false
        onPickerCancelled?()
    }
    
    func contentSharingPicker(_ picker: SCContentSharingPicker, didUpdateWith filter: SCContentFilter, for stream: SCStream?) {
        SCContentSharingPicker.shared.isActive = false
        selectedContentFilter = filter
        onContentSelected?(filter)
    }
    
    func contentSharingPickerStartDidFailWithError(_ error: any Error) {
        print("Window picker error: \(error.localizedDescription)")
        onPickerCancelled?()
    }
}
