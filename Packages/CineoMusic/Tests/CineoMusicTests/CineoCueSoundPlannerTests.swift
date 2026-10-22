import Foundation
import XCTest
@testable import CineoMusic

final class CineoCueSoundPlannerTests: XCTestCase {
    func testLegacyCuesHaveNoSoundUnlessEnabled() throws {
        let old = #"{"id":"c1","at":4,"kind":"hit","label":"Click"}"#
        let cue = try JSONDecoder().decode(CineoMusicCue.self, from: Data(old.utf8))
        XCTAssertNil(cue.soundEnabled)
        XCTAssertTrue(try CineoCueSoundPlanner.plan(cues: [cue], videoDuration: 8).isEmpty)
    }
    func testHitAndRiserAreTimedAgainstCue() throws {
        let events = try CineoCueSoundPlanner.plan(cues: [
            .init(id: "hit", at: 4, kind: .hit, soundEnabled: true, soundVolume: 0.5),
            .init(id: "rise", at: 3, kind: .crescendo, soundEnabled: true)
        ], videoDuration: 9)
        XCTAssertEqual(events.map(\.id), ["rise", "hit"])
        XCTAssertEqual(events[0].start, 2.25, accuracy: 1e-9)
        XCTAssertEqual(events[0].volume, 0.28, accuracy: 1e-9)
        XCTAssertEqual(events[1].start, 4)
        XCTAssertEqual(events[1].volume, 0.5)
    }
    func testRejectBadVolumeAndTooManyCueSounds() {
        XCTAssertThrowsError(try CineoCueSoundPlanner.plan(
            cues: [.init(id: "a", at: 2, kind: .hit,
                soundEnabled: true, soundVolume: 1.5)], videoDuration: 8))
        let excessive = (0...24).map {
            CineoMusicCue(id: "s\($0)", at: 1, kind: .hit, soundEnabled: true)
        }
        XCTAssertThrowsError(try CineoCueSoundPlanner.plan(
            cues: excessive, videoDuration: 8))
    }
}
