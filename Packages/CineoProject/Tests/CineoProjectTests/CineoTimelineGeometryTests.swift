import Foundation
import Testing
@testable import CineoProject

struct CineoTimelineGeometryTests {
    @Test func pixelSnapUsesViewportZoomNotFixedSeconds() throws {
        let wide = try CineoTimelineViewport(startSeconds: 0, endSeconds: 100, widthPixels: 1000)
        let narrow = try CineoTimelineViewport(startSeconds: 0, endSeconds: 10, widthPixels: 1000)
        #expect(wide.snappedTime(10.5, anchors: [10]) == 10)
        #expect(narrow.snappedTime(10, anchors: [9.5]) == 10)
        #expect(narrow.time(atPixel: 500) == 5)
        #expect(narrow.pixel(atTime: 5) == 500)
    }

    @Test func snapTieBreaksToEarlierAnchorAndOutsideClamps() throws {
        let view = try CineoTimelineViewport(startSeconds: 0, endSeconds: 10, widthPixels: 100)
        #expect(view.snappedTime(5, anchors: [5.6, 4.4]) == 4.4)
        #expect(view.time(atPixel: -10) == 0)
        #expect(view.time(atPixel: 200) == 10)
        #expect(view.pixel(atTime: -1) == 0)
    }

    @Test func regionMoveAndResizeBoundariesAndOverlap() throws {
        let region = try CineoTimelineRegion(id: "z", startSeconds: 2, endSeconds: 4)
        let blocker = try CineoTimelineRegion(id: "other", startSeconds: 5, endSeconds: 7)
        let moved = try #require(CineoTimelineEditEngine.applying(
            .move(startSeconds: 2.5), to: region, duration: 10, siblings: [blocker]))
        #expect(moved.startSeconds == 2.5)
        #expect(CineoTimelineEditEngine.applying(.move(startSeconds: 4), to: region,
                  duration: 10, siblings: [blocker]) == nil)
        let resize = try #require(CineoTimelineEditEngine.applying(
            .resizeEnd(seconds: 9), to: region, duration: 10))
        #expect(resize.endSeconds == 9)
        #expect(CineoTimelineEditEngine.applying(
            .resizeEnd(seconds: .nan), to: region, duration: 10) == nil)
    }

    @Test func invalidStateRejectedWithoutTouchingRegion() throws {
        #expect(throws: CineoTimelineError.invalidViewport) {
            try CineoTimelineViewport(startSeconds: 1, endSeconds: 1, widthPixels: 500)
        }
        let region = try CineoTimelineRegion(id: "a", startSeconds: 0, endSeconds: 1)
        #expect(CineoTimelineEditEngine.applying(.move(startSeconds: 4), to: region,
                  duration: 0) == nil)
        #expect(region.startSeconds == 0)
    }
}
