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
public enum CineoVideoTrackingDirection: Sendable {
    case forward
    case backward

    var sign: Double { self == .forward ? 1 : -1 }
}

public actor CineoVideoCursorTracker {
    public init() {}

    /// Recover positions both before and after the user-selected seed. Neither
    /// pass interpolates across tracking loss. The second direction is best-effort:
    /// a missing pointer before the seed must not erase a valid forward analysis.
    public func analyzeBidirectional(
        videoURL: URL, expectedSourceDuration: Double,
        seedSourceSeconds: Double, hotspotX: Double, hotspotY: Double,
        samplesPerSecond: Double = 6,
        progress: (@Sendable (Double) -> Void)? = nil
    ) async throws -> CineoImportedPointerAnalysis {
        var earlier: CineoImportedPointerAnalysis?
        if seedSourceSeconds > 0.2 {
            do {
                earlier = try await analyze(
                    videoURL: videoURL,
                    expectedSourceDuration: expectedSourceDuration,
                    seedSourceSeconds: seedSourceSeconds,
                    hotspotX: hotspotX, hotspotY: hotspotY,
                    direction: .backward, samplesPerSecond: samplesPerSecond,
                    progress: { value in progress?(value * 0.5) })
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                // Missing/occluded cursor before the seed: keep only trusted data.
            }
        }
        try Task.checkCancellation()
        progress?(0.5)
        var later: CineoImportedPointerAnalysis?
        if seedSourceSeconds < expectedSourceDuration - 0.2 {
            do {
                later = try await analyze(
                    videoURL: videoURL,
                    expectedSourceDuration: expectedSourceDuration,
                    seedSourceSeconds: seedSourceSeconds,
                    hotspotX: hotspotX, hotspotY: hotspotY,
                    direction: .forward, samplesPerSecond: samplesPerSecond,
                    progress: { value in progress?(0.5 + value * 0.5) })
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                // The valid reverse trace can still produce non-fabricated dwells.
            }
        }
        try Task.checkCancellation()
        progress?(1)
        switch (earlier, later) {
        case let (.some(before), .some(after)): return try before.merging(after)
        case let (.some(before), .none): return before
        case let (.none, .some(after)): return after
        default: throw CineoVideoTrackingError.insufficientTracking
        }
    }

    /// Scan from a manually selected cursor hotspot in the requested direction.
    /// Every emitted position is in SOURCE clock (not cut/output clock).
    /// - Note: Long videos are bounded to a 10-minute scan per direction. At most
    ///   6,000 frames are decoded. No cursor pixels are removed or re-drawn.
    public func analyze(videoURL: URL,
                        expectedSourceDuration: Double,
                        seedSourceSeconds: Double,
                        hotspotX: Double, hotspotY: Double,
                        direction: CineoVideoTrackingDirection = .forward,
                        samplesPerSecond: Double = 6,
                        progress: (@Sendable (Double) -> Void)? = nil) async throws
                        -> CineoImportedPointerAnalysis {
        guard videoURL.isFileURL,
              FileManager.default.isReadableFile(atPath: videoURL.path),
              expectedSourceDuration.isFinite && expectedSourceDuration > 0,
              seedSourceSeconds.isFinite && seedSourceSeconds >= 0 &&
                  seedSourceSeconds < expectedSourceDuration,
              (direction == .forward ? seedSourceSeconds < expectedSourceDuration - 0.15 :
               seedSourceSeconds > 0.15),
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

        let scanSeconds = min(600, 6_000 / samplesPerSecond)
        let lastTime = direction == .forward
            ? min(expectedSourceDuration - 0.05, seedSourceSeconds + scanSeconds)
            : max(0.05, seedSourceSeconds - scanSeconds)
        guard abs(lastTime - seedSourceSeconds) > 0.05 else {
            throw CineoVideoTrackingError.invalidSelection
        }
        var samples: [CineoImportedPointerSample] = [
            .init(sourceSeconds: seedSourceSeconds, x: hotspotX, y: hotspotY, confidence: 1)
        ]
        var failures = 0
        // Disabled by default. The benchmark opt-in reports only synthetic
        // cursor coordinates and confidence; never logs video pixels.
        let trace = ProcessInfo.processInfo.environment["CINEO_CURSOR_TRACE"] == "1"
        let step = 1 / samplesPerSecond
        var nextTime = seedSourceSeconds + direction.sign * step
        var previousTime = seedSourceSeconds
        while (direction == .forward ? nextTime < lastTime : nextTime > lastTime) &&
              samples.count < 6_000 {
            try Task.checkCancellation()
            var actualTime = CMTime.invalid
            let image: CGImage
            do {
                image = try generator.copyCGImage(
                    at: CMTime(seconds: nextTime, preferredTimescale: 600),
                    actualTime: &actualTime)
            } catch {
                if trace { print(String(format: "CURSOR_TRACE decode-failed time=%.3f", nextTime)) }
                failures += 1
                if failures >= 4 { break }
                nextTime += direction.sign * step
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
            if trace {
                print(String(format:
                    "CURSOR_TRACE time=%.3f actual=%.3f last=(%.1f,%.1f) patch=(%.1f,%.1f,%.2f,rmse=%.1f) vision=%.2f",
                    nextTime, CMTimeGetSeconds(actualTime),
                    latestX * Double(image.width), latestY * Double(image.height),
                    (patch?.x ?? -1) * Double(image.width),
                    (patch?.y ?? -1) * Double(image.height),
                    patch?.confidence ?? -1, patch?.errorPixels ?? -1,
                    Double(observation?.confidence ?? -1)))
            }
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
            let correctDirection = stamped.isFinite &&
                (stamped - previousTime) * direction.sign > 0
            let t = correctDirection ? stamped : nextTime
            if confidence >= 0.45, (0...1).contains(x), (0...1).contains(y),
               (t - previousTime) * direction.sign > 0 &&
               t >= 0 && t < expectedSourceDuration {
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
            nextTime += direction.sign * step
            progress?(min(1, abs(nextTime - seedSourceSeconds) /
                          max(0.01, abs(lastTime - seedSourceSeconds))))
        }
        try Task.checkCancellation()
        guard samples.count >= 3 else { throw CineoVideoTrackingError.insufficientTracking }
        progress?(1)
        return try CineoImportedPointerAnalysis(
            sourceDuration: expectedSourceDuration,
            seedSourceSeconds: seedSourceSeconds,
            samples: samples.sorted { $0.sourceSeconds < $1.sourceSeconds })
    }
}
