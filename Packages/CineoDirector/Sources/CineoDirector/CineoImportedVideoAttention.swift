import Foundation
import CineoEvents
import CineoScene

/// Cursor detections inferred from video pixels, NOT native mouse telemetry.
/// Never convert detections into clicks or into an independent-cursor overlay.
public struct CineoImportedPointerSample: Codable, Equatable, Sendable {
    public let sourceSeconds: Double
    public let x: Double
    public let y: Double
    public let confidence: Double

    public init(sourceSeconds: Double, x: Double, y: Double, confidence: Double) {
        self.sourceSeconds = sourceSeconds
        self.x = x
        self.y = y
        self.confidence = confidence
    }

    public var isValid: Bool {
        sourceSeconds.isFinite && sourceSeconds >= 0 &&
        x.isFinite && y.isFinite && (0...1).contains(x) && (0...1).contains(y) &&
        confidence.isFinite && (0...1).contains(confidence)
    }
}

public struct CineoImportedPointerAnalysis: Codable, Equatable, Sendable {
    public static let version = 1
    public let schemaVersion: Int
    public let sourceDuration: Double
    public let seedSourceSeconds: Double
    public let samples: [CineoImportedPointerSample]
    public let provenance: String

    public init(sourceDuration: Double, seedSourceSeconds: Double,
                samples: [CineoImportedPointerSample]) throws {
        self.schemaVersion = Self.version
        self.sourceDuration = sourceDuration
        self.seedSourceSeconds = seedSourceSeconds
        self.samples = samples
        self.provenance = "vision-manual-seed"
        try validate()
    }

    public func validate() throws {
        guard schemaVersion == Self.version, provenance == "vision-manual-seed",
              sourceDuration.isFinite && sourceDuration > 0,
              seedSourceSeconds.isFinite && seedSourceSeconds >= 0 &&
              seedSourceSeconds < sourceDuration,
              samples.count <= 30_000, !samples.isEmpty,
              samples.allSatisfy({ $0.isValid && $0.sourceSeconds < sourceDuration }),
              zip(samples, samples.dropFirst()).allSatisfy({
                  $0.0.sourceSeconds < $0.1.sourceSeconds
              })
        else { throw CineoImportedVideoError.invalidAnalysis }
    }

    /// Only reliable pixel-derived positions become movement; no fabricated clicks.
    public func movementEvents(minimumConfidence: Double = 0.65) -> [CineoPointerEvent] {
        guard minimumConfidence.isFinite, (0...1).contains(minimumConfidence) else { return [] }
        return samples.compactMap { sample in
            guard sample.confidence >= minimumConfidence else { return nil }
            return .init(sourceSeconds: sample.sourceSeconds,
                         x: sample.x, y: sample.y, kind: .moved)
        }
    }
}

public enum CineoImportedVideoError: Error, Equatable, Sendable {
    case invalidAnalysis
}

/// Inferred visual-attention holds. A stable pointer is NOT proof of clicking.
/// Short gaps, low-confidence samples and cuts cannot be bridged.
public struct CineoImportedVideoAttentionPlanner: Sendable {
    public struct Settings: Sendable {
        public var minimumConfidence: Double = 0.65
        public var maximumGap: Double = 0.34
        public var maximumDrift: Double = 0.055
        public var minimumDwell: Double = 0.75
        public var minimumEventsGap: Double = 1.0
        public init() {}
    }

    public init() {}

    public func inferredDwells(analysis: CineoImportedPointerAnalysis,
                               settings: Settings = .init()) -> [AttentionEvent] {
        guard (try? analysis.validate()) != nil,
              settings.minimumConfidence.isFinite &&
              (0...1).contains(settings.minimumConfidence),
              settings.maximumGap.isFinite && settings.maximumGap > 0,
              settings.maximumDrift.isFinite && settings.maximumDrift >= 0,
              settings.minimumDwell.isFinite && settings.minimumDwell > 0,
              settings.minimumEventsGap.isFinite && settings.minimumEventsGap > 0
        else { return [] }

        var runs: [[CineoImportedPointerSample]] = []
        var current: [CineoImportedPointerSample] = []
        for sample in analysis.samples {
            guard sample.confidence >= settings.minimumConfidence else {
                if !current.isEmpty { runs.append(current) }
                current = []
                continue
            }
            if let first = current.first, let last = current.last,
               (sample.sourceSeconds - last.sourceSeconds > settings.maximumGap ||
                hypot(sample.x - first.x, sample.y - first.y) > settings.maximumDrift) {
                runs.append(current)
                current = []
            }
            current.append(sample)
        }
        if !current.isEmpty { runs.append(current) }

        var events: [AttentionEvent] = []
        for run in runs {
            guard let first = run.first, let last = run.last,
                  last.sourceSeconds - first.sourceSeconds >= settings.minimumDwell
            else { continue }
            let moment = (first.sourceSeconds + last.sourceSeconds) / 2
            guard events.last.map({ moment - $0.time >= settings.minimumEventsGap }) ?? true
            else { continue }
            let x = run.map(\.x).reduce(0, +) / Double(run.count)
            let y = run.map(\.y).reduce(0, +) / Double(run.count)
            events.append(.init(time: moment, x: x, y: y, kind: .dwell))
        }
        return events
    }

    /// Use the existing camera shot and keyframe planning logic.
    public func propose(analysis: CineoImportedPointerAnalysis,
                        outputDuration: Double,
                        cutMapper: @Sendable (Double) -> Double?,
                        preset: CameraPreset = .balanced) -> CineoAutoEditProposal {
        guard outputDuration.isFinite, outputDuration > 0 else {
            return CineoAutoEditProposal(shots: [], keyframes: [])
        }
        let outputAttention = inferredDwells(analysis: analysis).compactMap { point -> AttentionEvent? in
            guard let output = cutMapper(point.time), output.isFinite,
                  output >= 0, output < outputDuration else { return nil }
            return .init(time: output, x: point.x, y: point.y, kind: .dwell)
        }
        let config = preset.configuration
        let shots = CameraPlanner(configuration: config).suggest(
            events: outputAttention, duration: outputDuration)
            .filter { $0.end < outputDuration - 0.02 }
        let keyframes = CineoAutoEditPlanner().keyframes(for: shots,
                                                         duration: outputDuration)
        return .init(shots: shots, keyframes: keyframes)
    }
}
