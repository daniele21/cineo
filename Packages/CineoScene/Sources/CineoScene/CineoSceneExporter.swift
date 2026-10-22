#if canImport(AVFoundation) && canImport(CoreImage)
import Foundation
import AVFoundation
import CoreImage
import CoreGraphics
import CoreVideo
import CineoProject

/// CLT-only Core Image/AVFoundation first-export experiment.
/// The same ScenePlan.evaluate(t) must drive future GUI preview and CLI export.
/// No Xcode.app, Metal shader compiler, FFmpeg, or Python dependency.
public struct CineoSceneExporter: Sendable {
    public init() {}

    /// Silent H.264 first slice. The recording source is read-only and the
    /// destination is created only after a complete, verified temporary export.
    public func export(source: URL, destination: URL,
                       plan: CineoScenePlan,
                       cuts: CineoCutList? = nil,
                       onProgress: (@Sendable (Double) -> Void)? = nil) async throws {
        try plan.validate()
        guard source.isFileURL, destination.isFileURL, source != destination,
              FileManager.default.fileExists(atPath: source.path),
              !FileManager.default.fileExists(atPath: destination.path)
        else { throw CineoSceneError.invalidDestination }
        let sourceAsset = AVURLAsset(url: source)
        guard let track = try await sourceAsset.loadTracks(withMediaType: .video).first else {
            throw CineoSceneError.invalidSource
        }
        let sourceSize = try await track.load(.naturalSize)
        let preferredTransform = try await track.load(.preferredTransform)
        // First milestone targets ScreenCaptureKit's unrotated display MP4.
        // Reject rather than silently export a rotated or mirrored movie.
        guard preferredTransform.isIdentity,
              sourceSize.width > 0, sourceSize.height > 0
        else { throw CineoSceneError.unsupportedSourceTransform }
        let duration = try await sourceAsset.load(.duration)
        if let cuts {
            try cuts.validate()
            guard abs(cuts.sourceDuration - duration.seconds) < 0.04 else {
                throw CineoSceneError.invalidSource
            }
        }
        let expectedDuration = cuts?.outputDuration ?? duration.seconds
        guard duration.isNumeric, duration.seconds > 0 else {
            throw CineoSceneError.invalidSource
        }

        // Temporary media sits beside the destination for same-volume promote.
        // NEVER delete/replace an existing user file or original recording.
        let temporary = destination.deletingLastPathComponent()
            .appendingPathComponent(".cineo-\(UUID().uuidString).mp4")
        let manager = FileManager.default
        var promoted = false
        defer {
            if !promoted { try? manager.removeItem(at: temporary) }
        }
        let reader = try AVAssetReader(asset: sourceAsset)
        let decoder = AVAssetReaderTrackOutput(track: track, outputSettings: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
        ])
        decoder.alwaysCopiesSampleData = false
        guard reader.canAdd(decoder) else { throw CineoSceneError.readerFailed }
        reader.add(decoder)

        let writer = try AVAssetWriter(outputURL: temporary, fileType: .mp4)
        let width = plan.outputWidth, height = plan.outputHeight
        let writerInput = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: width,
            AVVideoHeightKey: height,
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey: width * height * 5
            ]
        ])
        writerInput.expectsMediaDataInRealTime = false
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: writerInput,
            sourcePixelBufferAttributes: [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
                kCVPixelBufferWidthKey as String: width,
                kCVPixelBufferHeightKey as String: height,
                kCVPixelBufferIOSurfacePropertiesKey as String: [:] as [String: Any]
            ]
        )
        guard writer.canAdd(writerInput) else { throw CineoSceneError.writerFailed }
        writer.add(writerInput)
        guard reader.startReading(), writer.startWriting() else {
            throw CineoSceneError.writerFailed
        }
        writer.startSession(atSourceTime: .zero)
        let ciContext = CIContext(options: [.useSoftwareRenderer: false])
        let outputBounds = CGRect(x: 0, y: 0, width: CGFloat(width), height: CGFloat(height))
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bg = CIImage(color: CIColor(red: plan.background.red,
                                        green: plan.background.green,
                                        blue: plan.background.blue))
            .cropped(to: outputBounds)
        var firstPTS: CMTime?
        var frameCount = 0
        do {
            while let sample = decoder.copyNextSampleBuffer() {
                try Task.checkCancellation()
                guard let inputBuffer = CMSampleBufferGetImageBuffer(sample) else {
                    throw CineoSceneError.readerFailed
                }
                let pts = CMSampleBufferGetPresentationTimeStamp(sample)
                guard pts.isNumeric else { throw CineoSceneError.readerFailed }
                if firstPTS == nil { firstPTS = pts }
                guard let firstPTS else { throw CineoSceneError.readerFailed }
                let relativePTS = CMTimeSubtract(pts, firstPTS)
                guard relativePTS.isNumeric, relativePTS.seconds >= 0 else {
                    throw CineoSceneError.readerFailed
                }
                // Discard frames in cut regions, retime retained frames to a
                // contiguous output clock, and evaluate camera at OUTPUT time.
                guard let outputSeconds = cuts?.outputTime(
                    forSourceSeconds: relativePTS.seconds) ??
                    (cuts == nil ? relativePTS.seconds : nil) else { continue }
                let outputPTS = CMTime(seconds: outputSeconds, preferredTimescale: 60_000)
                guard let pool = adaptor.pixelBufferPool else {
                    throw CineoSceneError.writerFailed
                }
                var newBuffer: CVPixelBuffer?
                guard CVPixelBufferPoolCreatePixelBuffer(kCFAllocatorDefault, pool, &newBuffer) == kCVReturnSuccess,
                      let newBuffer
                else { throw CineoSceneError.writerFailed }
                let raw = CIImage(cvPixelBuffer: inputBuffer)
                let edited = try CineoSceneFrameRenderer.compose(
                    raw, at: outputSeconds, with: plan
                )
                ciContext.render(edited, to: newBuffer, bounds: outputBounds, colorSpace: colorSpace)
                while !writerInput.isReadyForMoreMediaData {
                    try Task.checkCancellation()
                    try await Task.sleep(for: .milliseconds(5))
                }
                guard adaptor.append(newBuffer, withPresentationTime: outputPTS) else {
                    throw CineoSceneError.writerFailed
                }
                frameCount += 1
                onProgress?(min(0.99, max(0, outputSeconds / expectedDuration)))
            }
            guard reader.status == .completed, frameCount > 0 else {
                throw CineoSceneError.readerFailed
            }
            writerInput.markAsFinished()
            await writer.finishWriting()
            guard writer.status == .completed else { throw CineoSceneError.writerFailed }

            let verified = AVURLAsset(url: temporary)
            let outTracks = try await verified.loadTracks(withMediaType: .video)
            let outDuration = try await verified.load(.duration)
            guard let outTrack = outTracks.first, outDuration.isNumeric,
                  outDuration.seconds > 0,
                  abs(outDuration.seconds - expectedDuration) < 0.35
            else { throw CineoSceneError.invalidOutput }
            let outSize = try await outTrack.load(.naturalSize)
            guard abs(outSize.width - CGFloat(width)) <= 1,
                  abs(outSize.height - CGFloat(height)) <= 1
            else { throw CineoSceneError.invalidOutput }
            try Task.checkCancellation()
            guard !manager.fileExists(atPath: destination.path) else {
                throw CineoSceneError.invalidDestination
            }
            try manager.moveItem(at: temporary, to: destination)
            promoted = true
            onProgress?(1)
        } catch {
            reader.cancelReading()
            writer.cancelWriting()
            throw error
        }
    }
}
#endif
