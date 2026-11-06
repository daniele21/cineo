import Foundation

/// A visual UI change detected from imported video pixels. This is NOT a mouse
/// click, keyboard action, or verified app event.
public struct CineoVisualAttentionCue: Codable, Sendable, Equatable {
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

    public var isValid: Bool {
        sourceSeconds.isFinite && sourceSeconds >= 0 &&
        x.isFinite && (0...1).contains(x) &&
        y.isFinite && (0...1).contains(y) &&
        confidence.isFinite && (0...1).contains(confidence) &&
        changedFraction.isFinite && (0...1).contains(changedFraction)
    }
}

public struct CineoAssistedZoomEvidence: Sendable, Equatable {
    public enum Origin: String, Sendable {
        case pointerDwell
        case visualChange
        case correlated
    }
    public let shot: CameraShot
    public let confidence: Double
    public let origin: Origin
}

public struct CineoImportedAssistedResult: Sendable {
    public let proposal: CineoAutoEditProposal
    /// Same order as proposal.shots; review hints only, never authoritative events.
    public let evidence: [CineoAssistedZoomEvidence]
}

/// Fuses cautiously inferred cursor dwells and pixel-derived UI changes.
/// The original video is untouched. Neither cue is ever turned into a click.
public struct CineoImportedAssistedPlanner: Sendable {
    public init() {}

    public func propose(
        pointerAnalysis: CineoImportedPointerAnalysis?,
        visualCues: [CineoVisualAttentionCue],
        outputDuration: Double,
        cutMapper: @Sendable (Double) -> Double?,
        preset: CameraPreset = .balanced
    ) -> CineoImportedAssistedResult {
        func empty() -> CineoImportedAssistedResult {
            .init(proposal: .init(shots: [], keyframes: []), evidence: [])
        }
        guard outputDuration.isFinite, outputDuration > 0 else { return empty() }

        struct Candidate {
            let time: Double
            let x: Double
            let y: Double
            let confidence: Double
            let origin: CineoAssistedZoomEvidence.Origin
        }

        let pointer = pointerAnalysis.map {
            CineoImportedVideoAttentionPlanner().inferredDwells(analysis: $0)
        } ?? []
        let mappedPointer = pointer.compactMap { point -> Candidate? in
            guard let time = cutMapper(point.time), time.isFinite,
                  time >= 0, time < outputDuration else { return nil }
            return .init(time: time, x: point.x, y: point.y,
                         confidence: 0.72, origin: .pointerDwell)
        }
        let mappedVisual = visualCues.compactMap { cue -> CineoVisualAttentionCue? in
            guard cue.isValid, cue.confidence >= 0.65, cue.changedFraction >= 0.12,
                  let mapped = cutMapper(cue.sourceSeconds), mapped.isFinite,
                  mapped >= 0, mapped < outputDuration else { return nil }
            return .init(sourceSeconds: mapped, x: cue.x, y: cue.y,
                         confidence: cue.confidence, changedFraction: cue.changedFraction)
        }.sorted { $0.sourceSeconds < $1.sourceSeconds }

        var consumedVisual = Set<Int>()
        var candidates: [Candidate] = []
        for point in mappedPointer {
            let best = mappedVisual.indices
                .filter { !consumedVisual.contains($0) }
                .filter {
                    abs(mappedVisual[$0].sourceSeconds - point.time) <= 1.25 &&
                    hypot(mappedVisual[$0].x - point.x, mappedVisual[$0].y - point.y) <= 0.25
                }
                .min {
                    abs(mappedVisual[$0].sourceSeconds - point.time) <
                    abs(mappedVisual[$1].sourceSeconds - point.time)
                }
            if let best {
                consumedVisual.insert(best)
                let change = mappedVisual[best]
                candidates.append(.init(time: point.time, x: point.x, y: point.y,
                                        confidence: min(1, 0.72 + 0.25 * change.confidence),
                                        origin: .correlated))
            } else {
                candidates.append(point)
            }
        }

        // Pixel changes are weaker than clicks. Only strong, localized changes
        // may independently suggest a camera move (including cursorless videos).
        for index in mappedVisual.indices where !consumedVisual.contains(index) {
            let cue = mappedVisual[index]
            guard cue.confidence >= 0.78, cue.changedFraction >= 0.20 else { continue }
            candidates.append(.init(time: cue.sourceSeconds, x: cue.x, y: cue.y,
                                    confidence: min(0.89, cue.confidence),
                                    origin: .visualChange))
        }
        candidates.sort {
            if $0.time != $1.time { return $0.time < $1.time }
            return $0.confidence > $1.confidence
        }
        guard !candidates.isEmpty else { return empty() }

        let events = candidates.map {
            AttentionEvent(time: $0.time, x: $0.x, y: $0.y, kind: .dwell)
        }
        let shots = CameraPlanner(configuration: preset.configuration)
            .suggest(events: events, duration: outputDuration)
            .filter { $0.end < outputDuration - 0.02 }
        let keyframes = CineoAutoEditPlanner().keyframes(
            for: shots, duration: outputDuration)
        let evidence = shots.map { shot -> CineoAssistedZoomEvidence in
            let nearest = candidates.min {
                abs($0.time - shot.start) < abs($1.time - shot.start)
            }!
            return .init(shot: shot, confidence: nearest.confidence,
                         origin: nearest.origin)
        }
        return .init(proposal: .init(shots: shots, keyframes: keyframes),
                     evidence: evidence)
    }
}
