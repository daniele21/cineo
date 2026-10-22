import Foundation

/// Optional, explicit sound design from a music cue. Sound events are output
/// timeline relative, rendered locally with procedural audio (no remote model).
public struct CineoCueSoundEvent: Equatable, Sendable {
    public let id: String
    public let at: Double
    public let kind: CineoMusicCueKind
    public let start: Double
    public let duration: Double
    public let volume: Double
}

public enum CineoCueSoundPlanner {
    public static let maximumEvents = 24

    public static func plan(cues: [CineoMusicCue],
                            videoDuration: Double) throws -> [CineoCueSoundEvent] {
        guard videoDuration.isFinite, videoDuration > 0 else {
            throw CineoMusicError.invalid("La durata del video è necessaria per gli effetti.")
        }
        let enabled = cues.filter { $0.soundEnabled == true }
        guard enabled.count <= maximumEvents else {
            throw CineoMusicError.invalid("Massimo 24 effetti sonori attivi per progetto.")
        }
        var events: [CineoCueSoundEvent] = []
        for cue in enabled {
            try cue.validate(videoDuration: videoDuration)
            let start: Double
            let length: Double
            switch cue.kind {
            case .hit:
                start = cue.at
                length = 0.25
            case .transition:
                start = max(0, cue.at - 0.18)
                length = 0.5
            case .crescendo:
                start = max(0, cue.at - 0.75)
                length = 0.82
            }
            let actualLength = min(length, videoDuration - start)
            guard actualLength > 0.015 else { continue }
            events.append(CineoCueSoundEvent(id: cue.id, at: cue.at,
                kind: cue.kind, start: start, duration: actualLength,
                volume: cue.soundVolume ?? 0.28))
        }
        return events.sorted { $0.start == $1.start ? $0.id < $1.id : $0.start < $1.start }
    }
}
