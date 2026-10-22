import Foundation
import CineoEvents
import CineoScene

/// A non-destructive proposal. Screen contents, keyboard input and fabricated
/// result anchors are deliberately not used: only opt-in mouse clicks.
public struct CineoAutoEditProposal: Sendable {
    public let shots: [CameraShot]
    public let keyframes: [CineoCameraKeyframe]

    public var isEmpty: Bool { shots.isEmpty }
}

public struct CineoAutoEditPlanner: Sendable {
    public init() {}

    public func propose(sidecar: CineoPointerSidecar, duration: Double,
                        preset: CameraPreset = .balanced) -> CineoAutoEditProposal {
        guard (try? sidecar.validate()) != nil, duration.isFinite, duration > 0 else {
            return CineoAutoEditProposal(shots: [], keyframes: [])
        }
        let clicks = sidecar.events.compactMap { event -> AttentionEvent? in
            guard event.kind == .leftClick || event.kind == .rightClick,
                  event.sourceSeconds < duration else { return nil }
            return AttentionEvent(time: event.sourceSeconds, x: event.x,
                                  y: event.y, kind: .click)
        }
        let shots = CameraPlanner(configuration: preset.configuration).suggest(
            events: clicks, duration: duration)
        let safeShots = shots.filter { shot in
            let length = shot.end - shot.start
            let transition = min(0.35, length * 0.26)
            return length >= 0.8 && shot.end <= duration &&
                shot.start + transition < shot.end - transition
        }
        return CineoAutoEditProposal(shots: safeShots,
                                      keyframes: keyframes(for: safeShots, duration: duration))
    }

    /// Rebuild from the user's selected proposals. This is deliberately the
    /// same recipe used for the initial preview: no second camera algorithm.
    /// Rejecting every proposal returns no frames and never modifies a project.
    public func keyframes(for shots: [CameraShot], duration: Double) -> [CineoCameraKeyframe] {
        guard duration.isFinite && duration > 0 else { return [] }
        var frames: [CineoCameraKeyframe] = []
        for shot in shots.sorted(by: { $0.start < $1.start }) {
            let length = shot.end - shot.start
            let transition = min(0.35, length * 0.26)
            guard shot.start.isFinite, shot.end.isFinite,
                  shot.start >= 0, shot.end <= duration, length >= 0.8,
                  shot.start + transition < shot.end - transition,
                  shot.focusX.isFinite, shot.focusY.isFinite, shot.zoom.isFinite,
                  (0...1).contains(shot.focusX), (0...1).contains(shot.focusY),
                  (1...3).contains(shot.zoom),
                  (frames.last?.time ?? -Double.infinity) < shot.start else { continue }
            let entry = shot.start + transition
            let release = shot.end - transition
            frames.append(.init(time: shot.start, zoom: 1, focusX: 0.5, focusY: 0.5))
            frames.append(.init(time: entry, zoom: shot.zoom, focusX: shot.focusX, focusY: shot.focusY))
            frames.append(.init(time: release, zoom: shot.zoom, focusX: shot.focusX, focusY: shot.focusY))
            frames.append(.init(time: shot.end, zoom: 1, focusX: 0.5, focusY: 0.5))
        }
        return frames
    }
}
