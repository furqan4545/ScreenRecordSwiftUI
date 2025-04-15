//
//  WindowAccessor.swift
//  ScreenRecord
//
//  Created by Furqan Ali on 4/7/25.
//

import Foundation
import SwiftUI
import AppKit

struct WindowAccessor: NSViewRepresentable {
    var callback: (NSWindow?) -> Void

    func makeNSView(context: Context) -> NSView {
        let nsView = NSView()
        DispatchQueue.main.async {
            self.callback(nsView.window)
        }
        return nsView
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}



// for older versions lower than macos 15.. we need to use appkit.. to keep the window always on top.. and below modifier is the way.. right now we
// are not using it anywhere..
struct WindowLevelModifier: ViewModifier {
    func body(content: Content) -> some View {
        content.background(
            WindowAccessor { window in
                window?.level = .floating
            }
        )
    }
}
