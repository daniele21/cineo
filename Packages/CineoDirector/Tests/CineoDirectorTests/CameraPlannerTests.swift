import Testing
@testable import CineoDirector

struct CameraPlannerTests {
    @Test func returnsNoShotsWithoutAttentionEvents() {
        #expect(CameraPlanner().suggest(events: [], duration: 15).isEmpty)
    }

    @Test func clustersManyNearClicksInsteadOfZoomStorm() {
        let events = (0..<40).map {
            AttentionEvent(time: 2 + Double($0) * 0.025, x: 0.5, y: 0.5, kind: .click)
        }
        let shots = CameraPlanner().suggest(events: events, duration: 15)
        #expect(shots.count == 1)
        #expect(shots[0].reason == .clickCluster)
        #expect(shots[0].end <= 15)
    }

    @Test func resultAnchorTakesPriorityAndClampsFrame() {
        let events = [
            AttentionEvent(time: 3, x: 0.5, y: 0.5, kind: .click),
            AttentionEvent(time: 3.5, x: 0.52, y: 0.52, kind: .result)
        ]
        let shots = CameraPlanner().suggest(events: events, duration: 12)
        #expect(shots.count == 1)
        guard let shot = shots.first else { return }
        #expect(shot.reason == .result)
        #expect(shot.focusX >= 0.5 / shot.zoom)
        #expect(shot.focusY <= 1 - 0.5 / shot.zoom)
    }

    @Test func ignoresInvalidTelemetry() {
        let events = [
            AttentionEvent(time: .nan, x: 0.5, y: 0.5, kind: .click),
            AttentionEvent(time: 0.3, x: -3, y: 0.5, kind: .click),
            AttentionEvent(time: 1, x: 0.5, y: 0.5, kind: .dwell)
        ]
        let shots = CameraPlanner().suggest(events: events, duration: 9)
        #expect(shots.count == 1)
        #expect(shots[0].reason == .dwell)
    }

    @Test func createsNonOverlappingBoundedShots() {
        let events = (0..<50).map {
            AttentionEvent(time: Double($0) * 2, x: $0.isMultiple(of: 2) ? 0.1 : 0.9, y: 0.5, kind: .click)
        }
        let shots = CameraPlanner().suggest(events: events, duration: 120)
        #expect(shots.count <= 24)
        for index in 1..<shots.count { #expect(shots[index].start >= shots[index - 1].end) }
    }

    @Test func isDeterministicWithOutOfOrderEvents() {
        let events = [AttentionEvent(time: 8, x: 0.8, y: 0.5, kind: .result), AttentionEvent(time: 3, x: 0.2, y: 0.2, kind: .click)]
        #expect(CameraPlanner().suggest(events: events, duration: 10) == CameraPlanner().suggest(events: events.reversed(), duration: 10))
    }
}
