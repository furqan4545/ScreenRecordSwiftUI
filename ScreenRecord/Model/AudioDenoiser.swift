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
        process.arguments = ["-o", outputDir.path, inputFileURL.path]
        
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
}
