import CoreGraphics
import Foundation

/// Cineo's intentionally conservative camera suggestions mapped into Orbit's
/// existing non-destructive zoom lane. Source PTS remains authoritative here:
/// Orbit's RenderPlan/TimeMap transforms zoom segments into output time.
nonisolated enum CineoAutoZoomBridge {

    static func segments(for telemetry: InputTelemetry, duration: Double) -> [ZoomSegment] {
        guard duration.isFinite, duration > 0 else { return [] }

        // Use only explicit click locations; never collect or infer typed text.
        // The native telemetry geometry mapper handles Retina scale/window crop.
        let events: [AttentionEvent] = telemetry.clicks.compactMap { click in
            guard click.isDown,
                  let p = telemetry.normalizedVideoPoint(for: click.location, at: click.time),
                  p.x.isFinite, p.y.isFinite,
                  (0...1).contains(p.x), (0...1).contains(p.y)
            else { return nil }
            return AttentionEvent(time: click.time, x: Double(p.x),
                                  y: Double(p.y), kind: .click)
        }

        // The director makes a small number of deliberate focus suggestions,
        // not a 2x jump at each input event. Unobservable outcomes must not be
        // fabricated; manual zooms and semantic anchors are separate features.
        let shots = CameraPlanner().suggest(events: events, duration: duration)

        return shots.map { shot in
            ZoomSegment(
                range: shot.start..<shot.end,
                scale: shot.zoom,
                focus: .fixed(center: ZoomSegment.clamped(
                    CGPoint(x: shot.focusX, y: shot.focusY), scale: shot.zoom
                )),
                isAutomatic: true
            )
        }
    }
}
