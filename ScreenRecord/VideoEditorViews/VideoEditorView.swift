//
//  VideoEditorView.swift
//  ScreenRecord
//
//  Created by Furqan Ali on 4/18/25.
//

import SwiftUI
import AVKit

struct VideoEditorView: View {
    @ObservedObject var viewModel: VideoEditorViewModel

    var body: some View {
        VStack(spacing: 0) {
            VideoPlayer(player: viewModel.player)
                .onAppear { viewModel.player.play() }
                .frame(
                  width: viewModel.editorSize.width,
                  height: viewModel.editorSize.height * 0.8
                )
            
            // placeholder for future editing controls
            HStack {
                Spacer()
                Text("Editing Controls →")
                    .foregroundColor(.secondary)
                Spacer()
            }
            .frame(height: viewModel.editorSize.height * 0.2)
        }
        .frame(
          minWidth: viewModel.editorSize.width,
          minHeight: viewModel.editorSize.height
        )
    }
}
