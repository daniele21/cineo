import Foundation
import AVFoundation
import CoreGraphics

/// A pixel-derived UI change, not an inferred click. No frames are persisted.
public struct CineoVisualChangeCandidate: Codable, Sendable, Equatable {
    public let sourceSeconds: Double
    public let x: Double
    public let y: Double
    public let confidence: Double
    public let changedFraction: Double

    public init(sourceSeconds: Double, x: Double, y: Double,
                confidence: Double, changedFraction: Double) {
        self.sourceSeconds = sourceSeconds
        self.x = x
        self.y = y
        self.confidence = confidence
        self.changedFraction = changedFraction
    }
}

/// Deterministic, resource-bounded pixel comparison. Rejects both tiny
/// compression noise and whole-frame cuts/flash transitions.
public struct CineoVisualChangeDetector: Sendable {
    public static let width = 64
    public static let height = 36

    public init() {}

    public func detect(previous: [UInt8], current: [UInt8],
                       sourceSeconds: Double) -> CineoVisualChangeCandidate? {
        let width = Self.width, height = Self.height
        guard sourceSeconds.isFinite && sourceSeconds >= 0,
              previous.count == width * height, current.count == width * height
        else { return nil }

        let tilesX = 8, tilesY = 6
        let tileW = width / tilesX, tileH = height / tilesY
        let tileArea = tileW * tileH
        var changedPerTile = [Int](repeating: 0, count: tilesX * tilesY)
        var allChanges = 0
        for y in 0..<height {
            for x in 0..<width {
                let idx = y * width + x
                // Grayscale difference >= 30 rejects ordinary H.264 quantization.
                guard abs(Int(current[idx]) - Int(previous[idx])) >= 30 else { continue }
                allChanges += 1
                changedPerTile[(y / tileH) * tilesX + (x / tileW)] += 1
            }
        }
        let globalFraction = Double(allChanges) / Double(width * height)
        // Under 2% is likely compression or a moving mouse. Over 65% is likely
        // a scene cut/flash, not a meaningful localized target.
        guard globalFraction >= 0.02 && globalFraction <= 0.65 else { return nil }
        let mostChanged = changedPerTile.enumerated().max { lhs, rhs in
            if lhs.element != rhs.element { return lhs.element < rhs.element }
            return lhs.offset > rhs.offset
        }!
        let localFraction = Double(mostChanged.element) / Double(tileArea)
        guard localFraction >= 0.23 else { return nil }

        let tx = mostChanged.offset % tilesX
        let ty = mostChanged.offset / tilesX
        let confidence = min(0.94, 0.58 + 0.45 * localFraction +
                             0.10 * min(1, globalFraction / 0.10))
        return .init(sourceSeconds: sourceSeconds,
                     x: (Double(tx) + 0.5) / Double(tilesX),
                     y: (Double(ty) + 0.5) / Double(tilesY),
                     confidence: confidence,
                     changedFraction: localFraction)
    }

    public func grayscale(_ frame: CGImage) -> [UInt8]? {
        let width = Self.width, height = Self.height
        var rgba = [UInt8](repeating: 0, count: width * height * 4)
        let success = rgba.withUnsafeMutableBytes { raw -> Bool in
            guard let ctx = CGContext(data: raw.baseAddress, width: width,
                                      height: height, bitsPerComponent: 8,
                                      bytesPerRow: width * 4,
                                      space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGBitmapInfo.byteOrder32Big.rawValue |
                                          CGImageAlphaInfo.premultipliedLast.rawValue)
            else { return false }
            ctx.interpolationQuality = .medium
            ctx.draw(frame, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard success else { return nil }
        return (0..<(width * height)).map { i in
            let offset = i * 4
            return UInt8(min(255, (77 * Int(rgba[offset]) +
                                   150 * Int(rgba[offset + 1]) +
                                    29 * Int(rgba[offset + 2])) >> 8))
        }
    }
}

public enum CineoVisualAnalysisError: Error, Sendable {
    case invalidVideo
}

/// Scans the source clock at bounded FPS using AVFoundation. Samples are
/// processed on-device; only timestamp, center, confidence and coverage escape.
public actor CineoVisualChangeAnalyzer {
    public init() {}

    public func analyze(videoURL: URL, expectedSourceDuration: Double,
                        samplesPerSecond: Double = 2,
                        progress: (@Sendable (Double) -> Void)? = nil) async throws
                        -> [CineoVisualChangeCandidate] {
        guard videoURL.isFileURL,
              FileManager.default.isReadableFile(atPath: videoURL.path),
              expectedSourceDuration.isFinite && expectedSourceDuration > 0.5,
              samplesPerSecond.isFinite && (0.5...4).contains(samplesPerSecond)
        else { throw CineoVisualAnalysisError.invalidVideo }

        let asset = AVURLAsset(url: videoURL)
        guard let track = try await asset.loadTracks(withMediaType: .video).first else {
            throw CineoVisualAnalysisError.invalidVideo
        }
        let duration = try await asset.load(.duration)
        let transform = try await track.load(.preferredTransform)
        guard duration.isNumeric,
              abs(duration.seconds - expectedSourceDuration) < 0.2,
              transform.isIdentity else { throw CineoVisualAnalysisError.invalidVideo }

        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 640, height: 640)
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero
        let detector = CineoVisualChangeDetector()
        let step = 1 / samplesPerSecond
        let lastTime = min(expectedSourceDuration - 0.05, 600)
        let totalFrames = min(1_200, Int(lastTime / step))
        guard totalFrames >= 2 else { return [] }

        var previous: [UInt8]?
        var changes: [CineoVisualChangeCandidate] = []
        var lastEmittedTime = -Double.infinity
        for n in 0..<totalFrames {
            try Task.checkCancellation()
            let time = min(lastTime, Double(n) * step)
            do {
                var actualTime = CMTime.invalid
                let image = try generator.copyCGImage(
                    at: CMTime(seconds: time, preferredTimescale: 600),
                    actualTime: &actualTime)
                guard let current = detector.grayscale(image) else { continue }
                if let previous {
                    let stamped = CMTimeGetSeconds(actualTime)
                    let t = stamped.isFinite && stamped >= 0 ? stamped : time
                    if t - lastEmittedTime >= 1.25,
                       let change = detector.detect(
                           previous: previous, current: current, sourceSeconds: t) {
                        changes.append(change)
                        lastEmittedTime = t
                    }
                }
                previous = current
            } catch {
                // A temporarily undecodable frame is not proof of an interaction;
                // clear the reference to avoid a fake giant difference.
                previous = nil
            }
            progress?(Double(n + 1) / Double(totalFrames))
        }
        try Task.checkCancellation()
        progress?(1)
        return changes
    }
}
