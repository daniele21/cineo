import Foundation

/// A cue is manually authored. Only an explicit confirmation may create
/// camera keyframes; the audio and original video are never altered.
public struct CineoCueCameraFrame: Equatable, Sendable {
    public let time: Double
    public let zoom: Double
    public let focusX: Double
    public let focusY: Double
    public init(time: Double, zoom: Double, focusX: Double, focusY: Double) {
        self.time = time
        self.zoom = zoom
        self.focusX = focusX
        self.focusY = focusY
    }
}

public struct CineoCueCameraSuggestion: Equatable, Sendable {
    public let cueID: String
    public let kind: CineoMusicCueKind
    public let frames: [CineoCueCameraFrame]
    public let description: String
}

public enum CineoCueCameraDirector {
    public static func propose(cue: CineoMusicCue, videoDuration: Double,
                               existing: [CineoBeatKeyframe],
                               focusX: Double, focusY: Double) -> CineoCueCameraSuggestion? {
        guard (try? cue.validate(videoDuration: videoDuration)) != nil,
              videoDuration.isFinite, videoDuration > 1,
              focusX.isFinite, (0...1).contains(focusX),
              focusY.isFinite, (0...1).contains(focusY),
              existing.allSatisfy({ $0.time.isFinite && $0.zoom.isFinite }) else { return nil }
        let t = cue.at
        var frames: [CineoCueCameraFrame] = []
        let description: String
        switch cue.kind {
        case .hit:
            // Arrive on the accent, hold, then return to wide context.
            guard t >= 0.35, t + 1.1 < videoDuration else { return nil }
            frames = [
                .init(time: t - 0.35, zoom: 1, focusX: 0.5, focusY: 0.5),
                .init(time: t, zoom: 1.5, focusX: focusX, focusY: focusY),
                .init(time: t + 0.35, zoom: 1.5, focusX: focusX, focusY: focusY),
                .init(time: t + 1.1, zoom: 1, focusX: 0.5, focusY: 0.5)
            ]
            description = "Hit: zoom sul cue con ritorno al campo largo"
        case .crescendo:
            guard t >= 0.05, t + 3.2 < videoDuration else { return nil }
            frames = [
                .init(time: t, zoom: 1, focusX: 0.5, focusY: 0.5),
                .init(time: t + 2, zoom: 1.65, focusX: focusX, focusY: focusY),
                .init(time: t + 2.55, zoom: 1.65, focusX: focusX, focusY: focusY),
                .init(time: t + 3.2, zoom: 1, focusX: 0.5, focusY: 0.5)
            ]
            description = "Crescendo: avvicinamento progressivo e ritorno"
        case .transition:
            // A compact emphasis and reveal using the existing renderer.
            guard t >= 0.45, t + 0.7 < videoDuration else { return nil }
            frames = [
                .init(time: t - 0.45, zoom: 1.35, focusX: focusX, focusY: focusY),
                .init(time: t, zoom: 1.35, focusX: focusX, focusY: focusY),
                .init(time: t + 0.7, zoom: 1, focusX: 0.5, focusY: 0.5)
            ]
            description = "Transizione: zoom out fino al campo largo"
        }
        guard let first = frames.first, let last = frames.last,
              !existing.contains(where: { $0.time >= first.time - 0.06 &&
                                          $0.time <= last.time + 0.06 })
        else { return nil }
        return CineoCueCameraSuggestion(cueID: cue.id, kind: cue.kind,
                                         frames: frames, description: description)
    }
}
