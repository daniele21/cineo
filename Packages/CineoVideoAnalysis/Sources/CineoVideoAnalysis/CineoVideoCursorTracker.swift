import Foundation
import AVFoundation
import Vision
import CoreGraphics
import CineoDirector

public enum CineoVideoTrackingError: Error, Equatable, Sendable {
    case invalidSource
    case invalidSelection
    case insufficientTracking
}

/// Native, local-only Vision tracker for cursor positions in a baked-in MP4.
/// The user explicitly identifies the cursor in an existing frame; automatic
/// cursor detection and click inference are NOT performed at this stage.
/// Neither video pixels nor window contents leave the local process.
public actor CineoVideoCursorTracker {
    public init() {}

    /// Scan forward from a manually selected cursor hotspot.
    /// Every emitted position is in SOURCE clock (not cut/output clock).
    /// - Note: Long videos are bounded to a 10-minute scan per seed. At most
    ///   6,000 frames are decoded. No cursor pixels are removed or re-drawn.
    public func analyze(videoURL: URL,
                        expectedSourceDuration: Double,
                        seedSourceSeconds: Double,
                        hotspotX: Double, hotspotY: Double,
                        samplesPerSecond: Double = 6,
                        progress: (@Sendable (Double) -> Void)? = nil) async throws
                        -> CineoImportedPointerAnalysis {
        guard videoURL.isFileURL,
              FileManager.default.isReadableFile(atPath: videoURL.path),
              expectedSourceDuration.isFinite && expectedSourceDuration > 0,
              seedSourceSeconds.isFinite && seedSourceSeconds >= 0 &&
                  seedSourceSeconds < expectedSourceDuration - 0.15,
              hotspotX.isFinite && hotspotY.isFinite,
              (0...1).contains(hotspotX), (0...1).contains(hotspotY),
              samplesPerSecond.isFinite &&
                  (2...12).contains(samplesPerSecond)
        else { throw CineoVideoTrackingError.invalidSelection }

        let asset = AVURLAsset(url: videoURL)
        guard let track = try await asset.loadTracks(withMediaType: .video).first else {
            throw CineoVideoTrackingError.invalidSource
        }
        let videoDuration = try await asset.load(.duration)
        let videoSize = try await track.load(.naturalSize)
        let preferredTransform = try await track.load(.preferredTransform)
        guard videoDuration.isNumeric && videoDuration.seconds > 0,
              abs(videoDuration.seconds - expectedSourceDuration) < 0.2,
              videoSize.width > 0, videoSize.height > 0,
              preferredTransform.isIdentity
        else { throw CineoVideoTrackingError.invalidSource }

        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 1280, height: 1280)
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero

        // Vision uses bottom-left normalized coordinates. The Cineo editor uses
        // top-left coordinates. The initial region is near the cursor tip.
        let width = min(0.075, max(0.018, 44.0 / videoSize.width))
        let height = min(0.10, max(0.025, 52.0 / videoSize.height))
        let visionX = max(0, min(1 - width, hotspotX - width * 0.35))
        let visionY = max(0, min(1 - height, 1 - hotspotY - height * 0.35))
        let initial = VNDetectedObjectObservation(
            boundingBox: CGRect(x: visionX, y: visionY, width: width, height: height))
        let tracker = VNTrackObjectRequest(detectedObjectObservation: initial)
        tracker.trackingLevel = .accurate
        let sequence = VNSequenceRequestHandler()
        // The first frame contains the user's real seed. Prime the sequence
        // with that frame BEFORE trying to follow a moving cursor at t + dt.
        // Otherwise the tracker can be asked to follow without having seen
        // the initial object in its image context.
        let firstImage = try generator.copyCGImage(
            at: CMTime(seconds: seedSourceSeconds, preferredTimescale: 600),
            actualTime: nil)
        try Task.checkCancellation()
        try sequence.perform([tracker], on: firstImage)
        let templateMatcher = CineoCursorTemplateMatcher(
            seed: firstImage, hotspotX: hotspotX, hotspotY: hotspotY)
        var latestX = hotspotX
        var latestY = hotspotY
        if let seeded = tracker.results?.first as? VNDetectedObjectObservation,
           seeded.confidence >= 0.35 {
            tracker.inputObservation = seeded
        }

        let lastTime = min(expectedSourceDuration - 0.05,
                           seedSourceSeconds + min(600, 6_000 / samplesPerSecond))
        guard lastTime > seedSourceSeconds else {
            throw CineoVideoTrackingError.invalidSelection
        }
        var samples: [CineoImportedPointerSample] = [
            .init(sourceSeconds: seedSourceSeconds, x: hotspotX, y: hotspotY, confidence: 1)
        ]
        var failures = 0
        let step = 1 / samplesPerSecond
        var nextTime = seedSourceSeconds + step
        var previousTime = seedSourceSeconds
        while nextTime < lastTime && samples.count < 6_000 {
            try Task.checkCancellation()
            var actualTime = CMTime.invalid
            let image: CGImage
            do {
                image = try generator.copyCGImage(
                    at: CMTime(seconds: nextTime, preferredTimescale: 600),
                    actualTime: &actualTime)
            } catch {
                failures += 1
                if failures >= 4 { break }
                nextTime += step
                continue
            }
            try Task.checkCancellation()
            var observation: VNDetectedObjectObservation?
            do {
                try sequence.perform([tracker], on: image)
                observation = tracker.results?.first as? VNDetectedObjectObservation
            } catch {
                // Visual patch matching remains available if Vision rejects a frame.
            }
            let patch = templateMatcher?.locate(in: image, aroundX: latestX, y: latestY)
            let x: Double, y: Double, confidence: Double
            if let patch, patch.confidence >= 0.65 {
                x = patch.x
                y = patch.y
                confidence = patch.confidence
            } else if let observation, observation.confidence >= 0.45 {
                let bounds = observation.boundingBox
                x = Double(bounds.minX + bounds.width * 0.35)
                y = Double(1 - bounds.maxY + bounds.height * 0.65)
                confidence = Double(observation.confidence)
            } else {
                failures += 1
                if failures >= 4 { break }
                nextTime += step
                continue
            }
            let stamped = CMTimeGetSeconds(actualTime)
            let t = stamped.isFinite && stamped > previousTime ? stamped : nextTime
            if confidence >= 0.45, (0...1).contains(x), (0...1).contains(y),
               t > previousTime && t < expectedSourceDuration {
                samples.append(.init(sourceSeconds: t, x: x, y: y,
                                     confidence: confidence))
                previousTime = t
                latestX = x
                latestY = y
                failures = 0
            } else {
                failures += 1
                if failures >= 4 { break }
            }
            if let observation {
                tracker.inputObservation = observation
            }
            nextTime += step
            progress?(min(1, (nextTime - seedSourceSeconds) /
                          max(0.01, lastTime - seedSourceSeconds)))
        }
        try Task.checkCancellation()
        guard samples.count >= 3 else { throw CineoVideoTrackingError.insufficientTracking }
        progress?(1)
        return try CineoImportedPointerAnalysis(
            sourceDuration: expectedSourceDuration,
            seedSourceSeconds: seedSourceSeconds, samples: samples)
    }
}
