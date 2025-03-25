//
//  AudioDenoiser.swift
//  ScreenRecord
//
//  Created by Furqan Ali on 3/25/25.
//
//
//  AudioDenoiser.swift
//  ScreenRecord
//
//  Created by [Your Name] on [Date].
//

import Foundation
import AVFoundation

/// A class that encapsulates file-based denoising using the DeepFilterNet binary.
class AudioDenoiser {
    
    private let binaryURL: URL
    private let outputDir: URL
    
    /// Initialize with the URL to the precompiled DeepFilterNet binary.
    /// The binary should be included in your app bundle.
    init(binaryURL: URL) {
        self.binaryURL = binaryURL
        // Create a temporary output directory for denoised files.
        self.outputDir = FileManager.default.temporaryDirectory.appendingPathComponent("DeepFilterOut", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: self.outputDir, withIntermediateDirectories: true, attributes: nil)
        } catch {
            print("Error creating output directory: \(error)")
        }
    }
    
    /// Processes an input WAV file using DeepFilterNet and returns the URL of the denoised file.
    /// - Parameters:
    ///   - inputFileURL: The URL to the input WAV file.
    ///   - completion: Completion block returning the output file URL or nil if processing failed.
    func denoiseFile(inputFileURL: URL, completion: @escaping (URL?) -> Void) {
        // Construct the output file URL in the output directory using the same file name.
        let outputFileURL = outputDir.appendingPathComponent(inputFileURL.lastPathComponent)
        
        // Configure the process.
        let process = Process()
        process.executableURL = binaryURL
        // According to DeepFilterNet docs, the binary usage is:
        // deep-filter [OPTIONS] [FILES]...
        // We pass the output directory with -o and the input file path.
        process.arguments = ["-o", outputDir.path, inputFileURL.path] // original
        
        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            print("Error running DeepFilterNet process: \(error.localizedDescription)")
            completion(nil)
            return
        }
        
        // Check for a nonzero termination status.
        if process.terminationStatus != 0 {
            print("DeepFilterNet process terminated with status \(process.terminationStatus)")
            completion(nil)
            return
        }
        
        // Verify that the output file exists.
        if FileManager.default.fileExists(atPath: outputFileURL.path) {
            completion(outputFileURL)
        } else {
            print("Denoised file not found at \(outputFileURL.path)")
            completion(nil)
        }
    }
    
    
    /// Enhances the audio file by denoising it and copying it to the downloads directory with a new name.
    /// - Parameters:
    ///   - inputURL: The URL to the microphone audio file.
    ///   - completion: Completion block returning the final enhanced file URL or nil if processing failed.
    func enhanceAudio(inputURL: URL, completion: @escaping (URL?) -> Void) {
        denoiseFile(inputFileURL: inputURL) { outputURL in
            guard let outputURL = outputURL else {
                completion(nil)
                return
            }
            do {
                // Create a new file name in the downloads folder.
                let downloadDir = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first!
                let originalFileName = inputURL.deletingPathExtension().lastPathComponent
                let enhancedFileName = "enhanced_\(originalFileName).wav"
                let finalURL = downloadDir.appendingPathComponent(enhancedFileName)
                
                // Remove existing file if it exists.
                if FileManager.default.fileExists(atPath: finalURL.path) {
                    try FileManager.default.removeItem(at: finalURL)
                }
                
                // Copy the denoised file to the downloads directory.
                try FileManager.default.copyItem(at: outputURL, to: finalURL)
                completion(finalURL)
            } catch {
                print("Error saving enhanced audio: \(error.localizedDescription)")
                completion(nil)
            }
        }
    }
}
