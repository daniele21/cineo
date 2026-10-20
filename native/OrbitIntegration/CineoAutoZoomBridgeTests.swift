import CoreGraphics
import Foundation
import Testing
@testable import Reco

/// Tests the *actual native conversion* into editable Orbit zoom segments.
/// Synthetic telemetry: no TCC permissions, screen recording or user content.
struct CineoAutoZoomBridgeTests {
    private func telemetry(clicks: [(Double, CGPoint)]) -> InputTelemetry {
        var t = InputTelemetry(
            capture: .init(kind: .display,
                           videoSize: CGSize(width: 1000, height: 500),
                           cursorInVideo: false),
            keystrokesAvailable: false
        )
        t.geometry = [.init(
            time: 0, screenRect: CGRect(x: 100, y: 200, width: 1000, height: 500),
            contentRect: CGRect(x: 0, y: 0, width: 1000, height: 500),
            boundingRect: nil, contentScale: 1, scaleFactor: 1
        )]
        t.clicks = clicks.map { time, point in
            .init(time: time, location: point, button: .left, isDown: true, clickCount: 1)
        }
        return t
    }

    @Test func recordedClickTurnsIntoRealAutomaticZoomSegment() {
        let input = telemetry(clicks: [
            (2, CGPoint(x: 600, y: 450)),
            (2.1, CGPoint(x: 605, y: 451)),
            (2.2, CGPoint(x: 605, y: 451))
        ])
        let segments = CineoAutoZoomBridge.segments(for: input, duration: 10)
        #expect(segments.count == 1)
        #expect(segments.first?.isAutomatic == true)
        #expect(segments.first?.scale == 1.4)
        #expect(segments.first?.range.lowerBound == 1.65)
        #expect(abs((segments.first?.range.upperBound ?? 0) - 3.4) < 0.000001)
        guard case .fixed(let center)? = segments.first?.focus else {
            Issue.record("Cineo expected editable fixed camera focus")
            return
        }
        #expect(center.x > 0.49 && center.x < 0.52)
        #expect(center.y > 0.49 && center.y < 0.52)
    }

    @Test func noTelemetryProducesNoFabricatedCameraMovement() {
        #expect(CineoAutoZoomBridge.segments(for: telemetry(clicks: []), duration: 10).isEmpty)
    }

    @Test func manualZoomIsNeverReplacedByRegeneration() {
        let input = telemetry(clicks: [(3, CGPoint(x: 600, y: 450))])
        let generated = CineoAutoZoomBridge.segments(for: input, duration: 10)
        let manual = ZoomSegment(
            range: 2.5..<4.5, scale: 1.6,
            focus: .fixed(center: CGPoint(x: 0.4, y: 0.6)),
            isAutomatic: false
        )
        let updated = [manual].regenerated(with: generated)
        #expect(updated.count == 1)
        #expect(updated[0].id == manual.id)
        #expect(updated[0].isAutomatic == false)
    }

    @Test func invalidCoordinatesAndClipEndAreSafelyIgnored() {
        let input = telemetry(clicks: [
            (0.5, CGPoint(x: -200, y: 450)),
            (9.99, CGPoint(x: 600, y: 450))
        ])
        let segments = CineoAutoZoomBridge.segments(for: input, duration: 10)
        #expect(segments.allSatisfy { $0.range.lowerBound >= 0 && $0.range.upperBound <= 10 })
        #expect(segments.count <= 1)
    }
    @Test func editorCameraPresetsChangeZoomStrengthWithoutChangingTimingBase() {
        let input = telemetry(clicks: [
            (2, CGPoint(x: 600, y: 450)),
            (2.1, CGPoint(x: 603, y: 450))
        ])
        let subtle = CineoAutoZoomBridge.segments(for: input, duration: 10, preset: .subtle)
        let balanced = CineoAutoZoomBridge.segments(for: input, duration: 10, preset: .balanced)
        let dynamic = CineoAutoZoomBridge.segments(for: input, duration: 10, preset: .dynamic)
        #expect(subtle.count == 1)
        #expect(balanced.count == 1)
        #expect(dynamic.count == 1)
        #expect(subtle[0].scale == 1.25)
        #expect(balanced[0].scale == 1.4)
        #expect(dynamic[0].scale == 1.65)
        #expect(subtle[0].isAutomatic && dynamic[0].isAutomatic)
    }

}
