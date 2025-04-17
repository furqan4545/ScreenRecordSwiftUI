//
//  VideoEditorVM.swift
//  ScreenRecord
//
//  Created by Furqan Ali on 4/18/25.
//

import Foundation
import AVKit
import Cocoa

class VideoEditorViewModel: ObservableObject {
    @Published var asset: VideoAsset
    @Published var player: AVPlayer
    
    /// Window size: 1/3 of screen width, 85% of screen height
    let editorSize: CGSize

    init(asset: VideoAsset) {
        self.asset = asset
        self.player = AVPlayer(url: asset.url)
        if let screen = NSScreen.main {
            let w = screen.visibleFrame.width * 0.33
            let h = screen.visibleFrame.height * 0.85
            editorSize = CGSize(width: w, height: h)
        } else {
            editorSize = CGSize(width: 800, height: 600)
        }
    }
}
