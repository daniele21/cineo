import Foundation
import CineoEvents
import CineoScene

/// Converts opt-in mouse telemetry into a few camera pan keyframes, without
/// changing zoom timing or replacing any original authored keyframe.
/// Every source sample has already been mapped to output time by the caller.
public struct CineoCameraFollowPlanner: Sendable {
    public struct Settings: Sendable, Equatable {
        public var safeInset: Double
        public var minimumInterval: Double
        public var protectedKeyframeRadius: Double
        public var minimumPan: Double
        public var maxAddedKeyframes: Int

        public init(safeInset: Double = 0.24, minimumInterval: Double = 0.18,
                    protectedKeyframeRadius: Double = 0.35,
                    minimumPan: Double = 0.025, maxAddedKeyframes: Int = 600) {
            self.safeInset = safeInset
            self.minimumInterval = minimumInterval
            self.protectedKeyframeRadius = protectedKeyframeRadius
            self.minimumPan = minimumPan
            self.maxAddedKeyframes = maxAddedKeyframes
        }
    }

    public init() {}

    /// Explicit, previewable follow suggestion: the calling editor must opt in
    /// and persist the returned scene only after validating it.
    public func propose(
        base: CineoScenePlan,
        movements: [CineoPointerEvent],
        duration: Double,
        settings: Settings = .init()
    ) throws -> [CineoCameraKeyframe] {
        try base.validate()
        guard duration.isFinite, duration > 0,
              settings.safeInset > 0, settings.safeInset < 0.5,
              settings.minimumInterval > 0,
              settings.protectedKeyframeRadius >= 0,
              settings.minimumPan >= 0, settings.maxAddedKeyframes > 0
        else { throw CineoSceneError.invalidPlan }
        guard base.camera.contains(where: { $0.zoom > 1.08 }) else { return base.camera }

        let ordered = movements
            .filter { $0.kind == .moved && $0.isValid &&
                      $0.sourceSeconds < duration }
            .sorted { $0.sourceSeconds < $1.sourceSeconds }

        var additions: [CineoCameraKeyframe] = []
        var lastEmission = -Double.infinity
        var latestPan: (x: Double, y: Double, zoom: Double)?
        for point in ordered {
            if additions.count >= settings.maxAddedKeyframes { break }
            let t = point.sourceSeconds
            guard t - lastEmission >= settings.minimumInterval else { continue }
            // Authored zoom/ramp boundaries always take precedence.
            guard !base.camera.contains(where: {
                abs($0.time - t) < settings.protectedKeyframeRadius
            }) else {
                latestPan = nil
                continue
            }

            let state = try base.evaluate(
                time: t, sourceWidth: 1920, sourceHeight: 1080)
            let zoom = 1 / state.cropWidth
            guard zoom > 1.08 else {
                latestPan = nil
                continue
            }

            let currentX: Double
            let currentY: Double
            if let previous = latestPan, abs(previous.zoom - zoom) < 0.03 {
                currentX = previous.x
                currentY = previous.y
            } else {
                currentX = state.cropX + state.cropWidth / 2
                currentY = state.cropY + state.cropHeight / 2
            }
            let halfSafe = (0.5 - settings.safeInset) / zoom
            let x = max(0, min(1, currentX))
            let y = max(0, min(1, currentY))
            let desiredX: Double
            let desiredY: Double
            if point.x > x + halfSafe {
                desiredX = point.x - halfSafe
            } else if point.x < x - halfSafe {
                desiredX = point.x + halfSafe
            } else {
                desiredX = x
            }
            if point.y > y + halfSafe {
                desiredY = point.y - halfSafe
            } else if point.y < y - halfSafe {
                desiredY = point.y + halfSafe
            } else {
                desiredY = y
            }
            let halfCrop = 0.5 / zoom
            let focusX = min(1 - halfCrop, max(halfCrop, desiredX))
            let focusY = min(1 - halfCrop, max(halfCrop, desiredY))
            guard hypot(focusX - x, focusY - y) >= settings.minimumPan else {
                continue
            }
            additions.append(.init(time: t, zoom: zoom, focusX: focusX, focusY: focusY))
            latestPan = (focusX, focusY, zoom)
            lastEmission = t
        }
        let merged = (base.camera + additions).sorted { $0.time < $1.time }
        var candidate = base
        candidate.camera = merged
        try candidate.validate()
        return merged
    }
}
