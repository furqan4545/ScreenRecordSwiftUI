////
////  ViewController.swift
////  ScreenRecord
////
////  Created by Furqan Ali on 3/24/25.
////
//
//import Foundation
//import AVFoundation
//import AVFAudio
//import Cocoa
//import ScreenCaptureKit
//
//class ViewController: NSViewController, SCStreamDelegate, SCStreamOutput {
//    
//    enum StreamType: Int {
//        case screen, window, systemAudio
//    }
//    
//    enum AudioQuality: Int {
//        case normal = 128, good = 192, high = 256, extreme = 320
//    }
//    
//    enum VideoFormat: String {
//        case mov, mp4
//    }
//    
//    var availableContent SCShareableContent?
//    var filter: SCContentFilter?
//    var screen: SCDisplay?
//    var audioSettings: [String: Any]!
//    var stream: SCStream!
//    var streamType: StreamType?
//    var vW: AVAssetWriter!
//    var recordMic = false
//    var vwInput, awInput, micInput: AVAssetWriterInput!
//    let audioEngine = AVAudioEngine()
//    
//    override func viewDidLoad() {
//        super.viewDidLoad()
//        
//        // do any additional setup after loading the view
//        let startButton = NSButton(title: "Start", target: self, action: #selector(startButtonClicked(_:)))
//        startButton.frame = NSRect(x: 50, y:50, width: 100, height: 40)
//        startButton.bezelStyle = .rounded
//        view.addSubView(startButton)
//        
//        // create stop button
//        let stopButton = NSButton(title: "Stop", target: self, action: #selector(stopButtonClicked(_:)))
//        stopButton.frame = NSRect(x: 200, y: 50, width: 100, height: 40)
//        stopButton.bezelStyle = .rounded
//        view.addSubView(stopButton)
//    }
//    
//    override var representedObject: Any? {
//        didSet {
//            // Update the view, if already Exist
//        }
//    }
//    
//    @objc func startButtonClicked(_, sender: NSButton) {
//        print("Start button Clicked")
//        // add your start Button logic here
//        
//        SCShareableContent.getExcludingDesktopWindows(true, onScreenWindowsOnly: true) { content, error in
//            if let error = error {
//                switch error {
//                case SCStreamError.userDeclined:
//                    print("hereeee")
//                    NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preferences.security?Privacy_ScreenCapture")!)
//                default: print("[Err] failed to fetch available content: ", error.localizedDescription)
//                }
//                return
//            }
//            self.availableContent = content
//            for (i, display) in self.availableContent!.displays.enumerated() {
//                let displayName = "Display \(i+1)" + displayID == CGMainDisplayID() ? " (Main)": "")
//                debugPrint(displayName)
//            }
//            self.prepRecord()
//        }
//    }
//    
//    @objc func stopButtonClicked(_ sender: NSButton) {
//        print("Stop button clicked")
//        // add your stop button logic here
//        stopRecording()
//    }
//    
//    func prepRecord() {
//        streamType = .screen
//        updateAudioSettings()
//        // todo check here
//        screen = availableContent!.displays.first
//        let excluded = availableContent?.applications.filter {
//            Bundle.main.bundleIdentifier == app.bundleIdentifier
//        }
//        filter = SCContentFilter(display: screen ?? availableContent!.displays.first!, excludingApplications: excluded ?? [], exceptingWindows: [])
//        Task { await record( filter: filter!) }
//    }
//    
//    func record(filter: SCContentFilter) async {
//        let conf = SCStreamConfiguration()
//        conf.width = 2
//        conf.height = 2
//        conf.width = Int(filter.contentRect.width) * Int(filter.pointPixelScale)
//        conf.height = Int(filter.contentRect.height) * Int(filter.pointPixelScale)
//        conf.minimumFrameInterval = CMTime(value: 1, timescale: CMTimeScale(60))
//        conf.showsCursor = true
//        conf.capturesAudio = true
//        conf.sampleRate = audioSettings["AVSampleRateKey"] as! Int
//        conf.channelCount = audioSettings["AvNumberOfChannelsKey"] as! Int
//        stream = SCStream(filter: filter, configuration: conf, delegate: self)
//        do {
//            try stream.addStreamOutput(self, type: .screen, sampleHandlerQueue: .global())
//            try stream.addStreamOutput(self, type: .audio, sampleHandlerQueue: .global())
//            initVideo(conf: conf)
//            try await stream.startCapture()
//            
//        } catch {
//            assertionFailure("captureFailed")
//            return
//        }
//    }
//    
//    func stopRecording() {
//        
//        if stream != nil {
//            stream.stopCapture()
//        }
//        stream = nil
//        closeVideo()
//        streamType = nil
//        
//    }
//    
//    func updateAudioSettings() {
//        audioSettings = [AVSampleRateKey: 48000, AVNumberOfChannelsKey: 2] // reset audio settings
//        // switch ud.string(forKey: "audioFormat" {
//        // case AudioFormat.aac.rawValue:
//        audioSettings[AVFormatIDKey] = kAudioFormatMPEG4AAC
//        audioSettings[AVEncoderBitRateKey] = AudioQuality.high.rawValue * 1000
//        //    case AudioFormat.alac.rawValue:
//        //        audioSettings[AVFormatIDKey] = kAudioFormatAppleLossless
//        //        audioSettings[AVEncoderBitDepthHintKey] = 16
//        //    case AudioFormat.flac.rawValue:
//        //        audioSettings[AVFormatIDKey] = kAudioFormatFLAC
//        //    case AudioFormat.opus.rawValue:
//        //        audioSettings[AVFormatIDKey] = ud.string(forKey: "videoFormat") != VideoFormat.mp4.rawValue ? kAudioFormatOpus : kAudioFormatMPEG4AAC
//        //        audioSettings[AVEncoderBitRateKey] = AudioQuality.extreme.rawValue * 1000
//        //    default:
//        //        assertionFailue("Unknown audio format while settings: " + (ud.string(forKey: "audioFormat") ?? "[no defaults]"))
//        //    }
//    }
//    
//    
//    func initVideo(conf: SCStreamConfiguration) {
//        let fileEnding = VideoFormat.mp4.rawValue
//        var fileType: AVFileType?
//        switch fileEnding {
//        case VideoFormat.mov.rawValue: fileType = AVFileType.mov
//        case VideoFormat.mp4.rawValue: fileType = AVFileType.mp4
//        default: assertionFailure("loaded unknown video format")
//        }
//        
//        if let downloadsDirectory = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first {
//            // Append the desired filename to the Downloads directory URL
//            let url = downloadsDirectory.appendingPathComponent("Recording\(Date()).\(fileEnding)")
//            vW = try? AVAssetWriter.init(outputURL: url, fileType: fileType!)
//            // let encoderIsH265 = false
//            
//            let fpsMultiplier: Double = Double(60) / 8
//            let encoderMultiplier: Double = 0.9
//            
//            let targetBitrate = (Double(conf.width) * Double(conf.height) * fpsMultiplier * encoderMultiplier)
//            let videoSettings: [String: Any] = [
//                AVVideoCodecKey: AVVideoCodecType.hevc,
//                // yes, not ideal if we want more than these encoders in the future, but it's ok for now
//                AVVideoWidthKey: conf.width,
//                AVVideoHeightKey: conf.height,
//                AVVideoCompressionPropertiesKey: [
//                    AVVideoAverageBitRateKey: targetBitrate,
//                    AVVideoExpectedSourceFrameRateKey: 60
//                ] as [String: Any]
//            ]
//            recordMic = false
//            
//            vwInput = AVAssetWriterInput(mediaType: AVMediaType.video, outputSettings: videoSettings)
//            awInput = AVAssetWriterInput(mediaType: AVMediaType.audio, outputSettings: audioSettings)
//            micInput = AVAssetWriterInput(mediaType: AVMediaType.audio, outputSettings: audioSettings)
//            
//            vwInput.expectsMediaDataInRealTime = true
//            awInput.expectsMediaDataInRealTime = true
//            micInput.expectsMediaDataInRealTime = true
//            
//            if vW.canAdd(vwInput) {
//                vW.add(vwInput)
//            }
//            
//            if vW.canAdd(awInput) {
//                vW.add(awInput)
//            }
//            
//            if recordMic {
//                if vW.canAdd(micInput) {
//                    vW.add(micInput)
//                }
//                
//                let input = audioEngine.inputNode
//                input.installTap(onBus: 0, bufferSize: 1024, format: input.inputFormat(forBus: 0)) { [self] (buffer, time) in
//                    if micInput.isReadyForMoreMediaData {
//                        micInput.append(buffer.asSampleBuffer!)
//                    }
//                }
//                try! audioEngine.start()
//            }
//            vW.startWriting()
//        } else {
//            print("Error: Downloads directory not found.")
//            return
//        }
//    }
//    func closeVideo() {
//        let dispatchGroup = DispatchGroup()
//        dispatchGroup.enter()
//        
//        vwInput.markAsFinished()
//        awInput.markAsFinished()
//        
//        if recordMic {
//            micInput.markAsFinished()
//            audioEngine.inputNode.removeTap(onBus: 0)
//            audioEngine.stop()
//        }
//        
//        vW.finishWriting {
//            dispatchGroup.leave()
//        }
//        
//        dispatchGroup.wait()
//        
//    }
//    
//    func stream(stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of outputType: SCStreamOutputType) {
//        guard sampleBuffer.isValid else { return }
//        
//        switch outputType {
//        case .screen:
//            guard let attachmentsArray = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: false) as? [[SCStreamFrameInfo: Any]],
//                  let attachments = attachmentsArray.first else { return }
//            guard let statusRawValue = attachments[SCStreamFrameInfo.status] as? Int,
//                  let status = SCFrameStatus(rawValue: statusRawValue),
//                  status == .complete else { return }
//            
//            if vW != nil && vW?.status == .writing {
//                vW.startSession(atSourceTime: CMSampleBufferGetPresentationTimeStamp(sampleBuffer))
//            }
//            
//            if vwInput.isReadyForMoreMediaData {
//                vwInput.append(sampleBuffer)
//            }
//            
//        case .audio:
//            // otherwise send the audio data to AVAssetWriter
//            if awInput.isReadyForMoreMediaData {
//                awInput.append(sampleBuffer)
//            }
//            
//        @unknown default:
//            assertionFailure("unknown stream type")
//        }
//    }
//    
//    func stream(_ stream: SCStream, didStopWithError error: Error) {
//        print("closing stream with error \n", error, "\n this might be due to the window closing or the user stopping from the sonoma ui")
//        DispatchQueue.main.async {
//            self.stream = nil
//            self.stopRecording()
//        }
//    }
//}
//
//extension AVAudioPCMBuffer {
//    var asSampleBuffer: CMSampleBuffer? {
//        let asbd = self.format.streamDescription
//        var sampleBuffer: CMSampleBuffer? = nil
//        var format: CMFormatDescription? = nil
//        
//        guard CMAudioFormatDescriptionCreate(
//            allocator: kCFAllocatorDefault,
//            asbd: asbd,
//            layoutSize: 0,
//            layout: nil,
//            magicCookieSize: 0,
//            magicCookie: nil,
//            extensions: nil,
//            formatDescriptionOut: &format
//        ) == noErr else { return nil }
//        
//        var timing = CMSampleTimingInfo(
//            duration: CMTime(value: 1, timescale: Int32(asbd.pointee.mSampleRate)),
//            presentationTimeStamp: CMClockGetTime(CMClockGetHostTimeClock()),
//            decodeTimeStamp: .invalid
//        )
//        
//        guard CMSampleBufferCreate(
//            allocator: kCFAllocatorDefault,
//            dataBuffer: nil,
//            dataReady: false,
//            makeDataReadyCallback: nil,
//            refcon: nil,
//            formatDescription: format,
//            sampleCount: CMItemCount(self.frameLength),
//            sampleTimingEntryCount: 1,
//            sampleTimingArray: &timing,
//            sampleSizeEntryCount: 0,
//            sampleSizeArray: nil,
//            sampleBufferOut: &sampleBuffer
//        ) == noErr else { return nil }
//        
//        guard CMSampleBufferSetDataBufferFromAudioBufferList(
//            sampleBuffer!,
//            blockBufferAllocator: kCFAllocatorDefault,
//            blockBufferMemoryAllocator: kCFAllocatorDefault,
//            flags: 0,
//            bufferList: self.mutableAudioBufferList
//        ) == noErr else { return nil }
//        
//        return sampleBuffer
//    }
//}
//
//extension CMSampleBuffer {
//    var asPCMBuffer: AVAudioPCMBuffer? {
//        try? self.withAudioBufferList { AudioBufferList, _ -> AVAudioPCMBuffer? in
//            guard let absd = self.formatDescription?.audioStreamBasicDescription else {return nil}
//            guard let format = AVAudioFormat(standardFormatWithSampleRate: absd.mSampleRate, channels: absd.mChannelsPerFrame) else {
//                    return nil
//            }
//        }
//    }
//}
//        
