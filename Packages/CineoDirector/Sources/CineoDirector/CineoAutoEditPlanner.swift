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
        // Every independent shot is a wide -> close -> hold -> wide sequence.
        // Avoid premature movement on single clicks near the end of a clip.
        var camera: [CineoCameraKeyframe] = []
        var accepted: [CameraShot] = []
        for shot in shots {
            let length = shot.end - shot.start
            guard length >= 0.8, shot.end <= duration else { continue }
            let transition = min(0.35, length * 0.26)
            let entry = shot.start + transition
            let release = shot.end - transition
            guard entry < release else { continue }
            if let last = camera.last, shot.start <= last.time + 0.001 { continue }
            camera.append(.init(time: shot.start, zoom: 1, focusX: 0.5, focusY: 0.5))
            camera.append(.init(time: entry, zoom: shot.zoom, focusX: shot.focusX, focusY: shot.focusY))
            camera.append(.init(time: release, zoom: shot.zoom, focusX: shot.focusX, focusY: shot.focusY))
            camera.append(.init(time: shot.end, zoom: 1, focusX: 0.5, focusY: 0.5))
            accepted.append(shot)
        }
        return CineoAutoEditProposal(shots: accepted, keyframes: camera)
    }
}
