#!/usr/bin/env swift

import AVFoundation
import CoreGraphics
import Foundation
import ImageIO

let width = 1080
let height = 1920
let fps: Int32 = 24
let expectedFrames = 360

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
let workDir = root.appendingPathComponent("outputs/promo/chickmark_tiny_manager_vertical", isDirectory: true)
let framesDir = workDir.appendingPathComponent("frames", isDirectory: true)
let tempVideoURL = workDir.appendingPathComponent("video_only.mov")
let finalURL = root.appendingPathComponent("outputs/promo/chickmark-tiny-manager-vertical.mp4")

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data("Error: \(message)\n".utf8))
    exit(1)
}

func removeIfExists(_ url: URL) {
    if FileManager.default.fileExists(atPath: url.path) {
        try? FileManager.default.removeItem(at: url)
    }
}

func sortedFrameURLs() throws -> [URL] {
    let urls = try FileManager.default.contentsOfDirectory(
        at: framesDir,
        includingPropertiesForKeys: nil,
        options: [.skipsHiddenFiles]
    )
    return urls
        .filter { $0.pathExtension.lowercased() == "png" }
        .sorted { $0.lastPathComponent < $1.lastPathComponent }
}

func makePixelBuffer(from url: URL, pool: CVPixelBufferPool) -> CVPixelBuffer? {
    guard let imageSource = CGImageSourceCreateWithURL(url as CFURL, nil),
          let cgImage = CGImageSourceCreateImageAtIndex(imageSource, 0, nil) else {
        return nil
    }

    var optionalBuffer: CVPixelBuffer?
    CVPixelBufferPoolCreatePixelBuffer(nil, pool, &optionalBuffer)
    guard let buffer = optionalBuffer else {
        return nil
    }

    CVPixelBufferLockBaseAddress(buffer, [])
    defer { CVPixelBufferUnlockBaseAddress(buffer, []) }

    guard let context = CGContext(
        data: CVPixelBufferGetBaseAddress(buffer),
        width: width,
        height: height,
        bitsPerComponent: 8,
        bytesPerRow: CVPixelBufferGetBytesPerRow(buffer),
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue
    ) else {
        return nil
    }

    context.clear(CGRect(x: 0, y: 0, width: width, height: height))
    context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
    return buffer
}

func encodeVideoOnly(frameURLs: [URL]) throws {
    removeIfExists(tempVideoURL)

    let writer = try AVAssetWriter(outputURL: tempVideoURL, fileType: .mov)
    let settings: [String: Any] = [
        AVVideoCodecKey: AVVideoCodecType.h264,
        AVVideoWidthKey: width,
        AVVideoHeightKey: height,
        AVVideoCompressionPropertiesKey: [
            AVVideoAverageBitRateKey: 8_000_000,
            AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel,
        ],
    ]

    let input = AVAssetWriterInput(mediaType: .video, outputSettings: settings)
    input.expectsMediaDataInRealTime = false

    let adaptor = AVAssetWriterInputPixelBufferAdaptor(
        assetWriterInput: input,
        sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32ARGB,
            kCVPixelBufferWidthKey as String: width,
            kCVPixelBufferHeightKey as String: height,
            kCVPixelBufferCGImageCompatibilityKey as String: true,
            kCVPixelBufferCGBitmapContextCompatibilityKey as String: true,
        ]
    )

    guard writer.canAdd(input) else {
        fail("AVAssetWriter cannot add video input.")
    }
    writer.add(input)

    guard writer.startWriting() else {
        fail("AVAssetWriter could not start writing: \(writer.error?.localizedDescription ?? "unknown error")")
    }
    writer.startSession(atSourceTime: .zero)

    let semaphore = DispatchSemaphore(value: 0)
    let queue = DispatchQueue(label: "chickmark.promo.video.input")
    let frameDuration = CMTime(value: 1, timescale: fps)
    var index = 0
    var appendError: String?

    input.requestMediaDataWhenReady(on: queue) {
        guard let pool = adaptor.pixelBufferPool else {
            appendError = "Pixel buffer pool was not created."
            input.markAsFinished()
            writer.cancelWriting()
            semaphore.signal()
            return
        }

        while input.isReadyForMoreMediaData && index < frameURLs.count {
            autoreleasepool {
                let url = frameURLs[index]
                guard let buffer = makePixelBuffer(from: url, pool: pool) else {
                    appendError = "Could not create pixel buffer for \(url.lastPathComponent)."
                    return
                }
                let time = CMTimeMultiply(frameDuration, multiplier: Int32(index))
                if !adaptor.append(buffer, withPresentationTime: time) {
                    appendError = "Could not append \(url.lastPathComponent): \(writer.error?.localizedDescription ?? "unknown error")"
                }
            }

            if appendError != nil {
                input.markAsFinished()
                writer.cancelWriting()
                semaphore.signal()
                return
            }
            index += 1
        }

        if index >= frameURLs.count {
            input.markAsFinished()
            writer.finishWriting {
                semaphore.signal()
            }
        }
    }

    semaphore.wait()

    if let appendError {
        fail(appendError)
    }
    if writer.status != .completed {
        fail("Video-only encode did not complete: \(writer.error?.localizedDescription ?? "status \(writer.status.rawValue)")")
    }
}

func mergeVideoAndAudio() throws {
    removeIfExists(finalURL)

    let videoAsset = AVURLAsset(url: tempVideoURL)
    guard let sourceVideoTrack = videoAsset.tracks(withMediaType: .video).first else {
        fail("Temporary video has no video track.")
    }

    let composition = AVMutableComposition()
    guard let compositionVideoTrack = composition.addMutableTrack(
        withMediaType: .video,
        preferredTrackID: kCMPersistentTrackID_Invalid
    ) else {
        fail("Could not create composition video track.")
    }

    let duration = videoAsset.duration
    try compositionVideoTrack.insertTimeRange(
        CMTimeRange(start: .zero, duration: duration),
        of: sourceVideoTrack,
        at: .zero
    )
    compositionVideoTrack.preferredTransform = sourceVideoTrack.preferredTransform

    guard let export = AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetHighestQuality) else {
        fail("Could not create export session.")
    }

    guard export.supportedFileTypes.contains(.mp4) else {
        fail("MP4 export is not supported by this export session. Supported: \(export.supportedFileTypes)")
    }

    export.outputURL = finalURL
    export.outputFileType = .mp4
    export.shouldOptimizeForNetworkUse = true
    export.timeRange = CMTimeRange(start: .zero, duration: duration)

    let semaphore = DispatchSemaphore(value: 0)
    export.exportAsynchronously {
        semaphore.signal()
    }
    semaphore.wait()

    if export.status != .completed {
        fail("Final export failed: \(export.error?.localizedDescription ?? "status \(export.status.rawValue)")")
    }
}

do {
    guard FileManager.default.fileExists(atPath: framesDir.path) else {
        fail("Frames directory does not exist. Run generate_chickmark_promo.py first.")
    }

    let frameURLs = try sortedFrameURLs()
    guard frameURLs.count == expectedFrames else {
        fail("Expected \(expectedFrames) frames, found \(frameURLs.count).")
    }

    print("Encoding \(frameURLs.count) frames at \(fps) FPS...")
    try encodeVideoOnly(frameURLs: frameURLs)
    print("Exporting silent MP4...")
    try mergeVideoAndAudio()
    print("Video: \(finalURL.path)")
} catch {
    fail(error.localizedDescription)
}
