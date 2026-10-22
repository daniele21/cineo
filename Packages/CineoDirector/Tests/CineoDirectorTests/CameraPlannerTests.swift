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
    @Test func equalTimestampOrderCannotChangeSuggestedShot() {
        let events = [
            AttentionEvent(time: 1, x: 0.20, y: 0.6, kind: .click),
            AttentionEvent(time: 1, x: 0.24, y: 0.6, kind: .result),
            AttentionEvent(time: 1, x: 0.30, y: 0.6, kind: .result)
        ]
        let planner = CameraPlanner()
        #expect(planner.suggest(events: events, duration: 10) ==
                planner.suggest(events: events.reversed(), duration: 10))
        #expect(planner.suggest(events: events, duration: 10).first?.reason == .result)
    }

    @Test func longClickStreamIsSplitIntoFiniteGroups() {
        let events = (0..<35).map {
            AttentionEvent(time: Double($0) * 0.4 + 1, x: 0.5, y: 0.5, kind: .click)
        }
        var config = CameraPlanner.Configuration()
        config.duplicateSuppressionTime = 0
        let shots = CameraPlanner(configuration: config).suggest(events: events, duration: 30)
        #expect(shots.count >= 2)
        #expect(shots.allSatisfy { $0.end - $0.start < 10 })
    }

    @Test func frequentActionsCannotConsumeWholeMinuteBudgetAtOnce() {
        let events = (0..<50).map {
            AttentionEvent(time: Double($0) * 1.1, x: $0.isMultiple(of: 2) ? 0.1 : 0.9, y: 0.5, kind: .click)
        }
        var config = CameraPlanner.Configuration()
        config.maxShotsPerMinute = 5
        let shots = CameraPlanner(configuration: config).suggest(events: events, duration: 180)
        #expect(shots.filter { $0.start < 60 }.count <= 5)
    }

    @Test func denseClicksDoNotCreateDelayedOffTargetZooms() {
        let events = [
            AttentionEvent(time: 1.0, x: 0.10, y: 0.10, kind: .click),
            AttentionEvent(time: 2.3, x: 0.90, y: 0.90, kind: .click),
            AttentionEvent(time: 7.0, x: 0.20, y: 0.80, kind: .click)
        ]
        let shots = CameraPlanner().suggest(events: events, duration: 12)
        #expect(shots.count == 2)
        #expect(shots[0].start <= 1.0)
        #expect(shots[1].start <= 7.0)
    }

    @Test func nearEndEventCannotProduceOutOfBoundsShot() {
        let events = [
            AttentionEvent(time: 1, x: 0.2, y: 0.2, kind: .click),
            AttentionEvent(time: 1.7, x: 0.8, y: 0.8, kind: .click)
        ]
        let shots = CameraPlanner().suggest(events: events, duration: 1.8)
        #expect(shots.allSatisfy { $0.start >= 0 && $0.start < $0.end && $0.end <= 1.8 })
    }

    @Test func unreasonableConfigurationFailsClosed() {
        var config = CameraPlanner.Configuration()
        config.maximumEventGap = .nan
        #expect(CameraPlanner(configuration: config).suggest(
            events: [AttentionEvent(time: 0.1, x: 0.5, y: 0.5, kind: .click)],
            duration: 4
        ).isEmpty)
    }

    @Test func repeatClickAtSameLocationDoesNotCauseJitteryZooms() {
        let events = [
            AttentionEvent(time: 1, x: 0.3, y: 0.3, kind: .click),
            AttentionEvent(time: 2.5, x: 0.3, y: 0.3, kind: .click)
        ]
        let shots = CameraPlanner().suggest(events: events, duration: 15)
        #expect(shots.count == 1)
    }

    @Test func explicitResultAnchorRetainsReadabilityGap() {
        let events = [
            AttentionEvent(time: 1, x: 0.3, y: 0.3, kind: .click),
            AttentionEvent(time: 2.5, x: 0.3, y: 0.3, kind: .result)
        ]
        let shots = CameraPlanner().suggest(events: events, duration: 15)
        #expect(shots.count == 2)
        #expect(shots[1].reason == .result)
        #expect(shots[1].start >= shots[0].end + 0.2)
        #expect(shots[1].start <= 2.5)
    }

    @Test func explicitResultAnchorSurvivesDuplicateSuppression() {
        let events = [
            AttentionEvent(time: 1, x: 0.3, y: 0.3, kind: .click),
            AttentionEvent(time: 2.5, x: 0.3, y: 0.3, kind: .result)
        ]
        let shots = CameraPlanner().suggest(events: events, duration: 15)
        #expect(shots.contains { $0.reason == .result })
    }

}
