import CoreGraphics
import Foundation
import Testing
@testable import Reco

/// Native compositor camera-motion contract using synthetic timing/focus.
/// Checks the exact CameraPath that both preview and exported RenderPlan use.
/// This is NOT a pixel-level visual comparison or a media export test.
struct CineoCameraMotionTests {
    @Test func zoomSpringDoesNotJumpOrLeaveValidFrame() {
        let zoom = ZoomSegment(range: 1..<4, scale: 1.6,
                               focus: .fixed(center: CGPoint(x: 0.96, y: 0.06)),
                               isAutomatic: true)
        let camera = CameraPath(zooms: [zoom], cursor: [], duration: 7)
        let sampleTimes = stride(from: 0.0, through: 7.0, by: 1.0/60)
        var prior: CameraPath.Viewport?
        var peak = 1.0
        for time in sampleTimes {
            let frame = camera.viewport(at: time)
            #expect(frame.scale.isFinite)
            #expect(frame.scale >= 1)
            #expect(frame.center.x.isFinite && frame.center.y.isFinite)
            let margin = 0.5 / frame.scale
            #expect(frame.center.x >= margin - 0.00001)
            #expect(frame.center.x <= 1 - margin + 0.00001)
            #expect(frame.center.y >= margin - 0.00001)
            #expect(frame.center.y <= 1 - margin + 0.00001)
            if let prior {
                // A spring camera sampled at 60 Hz should never teleport a
                // tenth of the frame in one rendered tick.
                #expect(abs(frame.center.x - prior.center.x) < 0.1)
                #expect(abs(frame.center.y - prior.center.y) < 0.1)
                #expect(abs(frame.scale - prior.scale) < 0.1)
            }
            peak = max(peak, frame.scale)
            prior = frame
        }
        #expect(peak > 1.25)
        #expect(camera.viewport(at: 0).scale == 1)
    }

    @Test func previewAndExportUseIdenticalCameraPathForSameGeometry() {
        let zoom = ZoomSegment(range: 1..<4, scale: 1.4,
                               focus: .fixed(center: CGPoint(x: 0.2, y: 0.7)),
                               isAutomatic: true)
        let preview = CameraPath(zooms: [zoom], cursor: [], duration: 6)
        let export = CameraPath(zooms: [zoom], cursor: [], duration: 6)
        for t in stride(from: 0.0, through: 6.0, by: 0.25) {
            #expect(preview.viewport(at: t) == export.viewport(at: t))
        }
    }

    @Test func sourceZoomIntervalsMapToEditedOutputTime() {
        let timeMap = TimeMap(cuts: [2..<4], sourceDuration: 10, frameRate: 30)
        let source = ZoomSegment(range: 5..<7, scale: 1.4,
                                 focus: .fixed(center: CGPoint(x: 0.5, y: 0.5)),
                                 isAutomatic: true)
        let mapped = RenderPlan.outputZooms([source], timeMap: timeMap)
        #expect(mapped.count == 1)
        #expect(abs(mapped[0].range.lowerBound - 3) < 0.00001)
        #expect(abs(mapped[0].range.upperBound - 5) < 0.00001)
        #expect(mapped[0].scale == source.scale)
    }

    @Test func noCameraEventsStayAtWholeFrame() {
        let camera = CameraPath(zooms: [], cursor: [], duration: 20)
        #expect(camera.viewport(at: 0) == .whole)
        #expect(camera.viewport(at: 10) == .whole)
    }
}
