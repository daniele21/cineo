import Foundation
import Testing
@testable import CineoEvents

struct CineoPointerMotionTrackTests {
    @Test func exactClickAnchorWinsAtDuplicateTimestamp() throws {
        let track = try CineoPointerMotionTrack(events: [
            .init(sourceSeconds: 0, x: 0.1, y: 0.2, kind: .moved),
            .init(sourceSeconds: 0.1, x: 0.5, y: 0.4, kind: .moved),
            .init(sourceSeconds: 0.1, x: 0.6, y: 0.45, kind: .leftClick),
            .init(sourceSeconds: 0.2, x: 0.8, y: 0.7, kind: .moved)
        ])
        let click = try #require(track.position(at: 0.1))
        #expect(click.anchoredToClick)
        #expect(click.x == 0.6)
        #expect(click.y == 0.45)
        #expect(!((try #require(track.position(at: 0.15))).anchoredToClick))
    }

    @Test func arbitrarySeekOrderIsDeterministic() throws {
        let track = try CineoPointerMotionTrack(events: [
            .init(sourceSeconds: 1, x: 0, y: 0, kind: .moved),
            .init(sourceSeconds: 1.2, x: 1, y: 1, kind: .moved)
        ])
        let ordered = [1.0, 1.05, 1.1, 1.15, 1.2].map {
            track.position(at: $0, interpolation: .easeInOut)
        }
        let reversed = [1.2, 1.15, 1.1, 1.05, 1.0].map {
            track.position(at: $0, interpolation: .easeInOut)
        }
        #expect(ordered == reversed.reversed())
        #expect(try #require(track.position(at: 1.1)).x > 0.49)
        #expect(try #require(track.position(at: 1.1)).x < 0.51)
    }

    @Test func missingTelemetryAndLargeGapsFailClosed() throws {
        let clicks = try CineoPointerMotionTrack(events: [
            .init(sourceSeconds: 2, x: 0.1, y: 0.2, kind: .leftClick),
            .init(sourceSeconds: 2.2, x: 0.9, y: 0.8, kind: .rightClick)
        ])
        #expect(clicks.position(at: 2.1) == nil)
        #expect(clicks.position(at: 2) != nil)
        #expect(clicks.position(at: 3) == nil)
        let gap = try CineoPointerMotionTrack(events: [
            .init(sourceSeconds: 0, x: 0, y: 0, kind: .moved),
            .init(sourceSeconds: 1, x: 1, y: 1, kind: .moved)
        ])
        #expect(gap.position(at: 0.5) == nil)
        #expect(gap.position(at: 0.5, maximumGap: 1.1) != nil)
    }

    @Test func rejectsCorruptOrUnsortedSamples() {
        #expect(throws: CineoEventsError.invalidEvent) {
            try CineoPointerMotionTrack(events: [
                .init(sourceSeconds: 1, x: 0.5, y: 0.5, kind: .moved),
                .init(sourceSeconds: 0, x: 0.2, y: 0.3, kind: .moved)
            ])
        }
        #expect(throws: CineoEventsError.invalidEvent) {
            try CineoPointerMotionTrack(events: [
                .init(sourceSeconds: 1, x: .nan, y: 0.4, kind: .moved)
            ])
        }
    }
}
