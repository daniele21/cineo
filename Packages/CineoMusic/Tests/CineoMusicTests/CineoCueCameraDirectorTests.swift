import Foundation
import XCTest
@testable import CineoMusic

final class CineoCueCameraDirectorTests: XCTestCase {
    func testHitCreatesNonDestructiveFourFrameSuggestionOnCue() {
        let cue = CineoMusicCue(id: "hit-1", at: 3, kind: .hit)
        let value = CineoCueCameraDirector.propose(cue: cue, videoDuration: 15,
            existing: [], focusX: 0.8, focusY: 0.3)
        XCTAssertEqual(value?.frames.count, 4)
        XCTAssertEqual(value?.frames.map(\.time), [2.65, 3, 3.35, 4.1])
        XCTAssertEqual(value?.frames[1].focusX, 0.8)
        XCTAssertEqual(value?.frames.last?.zoom, 1)
    }

    func testCrescendoAndTransitionGenerateDifferentShots() {
        let build = CineoCueCameraDirector.propose(
            cue: .init(id: "a", at: 2, kind: .crescendo),
            videoDuration: 20, existing: [], focusX: 0.2, focusY: 0.4)
        let transition = CineoCueCameraDirector.propose(
            cue: .init(id: "b", at: 9, kind: .transition),
            videoDuration: 20, existing: [], focusX: 0.2, focusY: 0.4)
        XCTAssertEqual(build?.frames.count, 4)
        XCTAssertEqual(build?.frames[1].time, 4)
        XCTAssertEqual(transition?.frames.count, 3)
        XCTAssertEqual(transition?.frames.last?.time, 9.7)
    }

    func testNeverOverwritesExistingCameraOrCreatesOutOfBoundShots() {
        let cue = CineoMusicCue(id: "cue", at: 3, kind: .hit)
        XCTAssertNil(CineoCueCameraDirector.propose(cue: cue, videoDuration: 20,
            existing: [.init(time: 3.5, zoom: 2)], focusX: 0.5, focusY: 0.5))
        XCTAssertNil(CineoCueCameraDirector.propose(cue: .init(at: 0.1, kind: .hit),
            videoDuration: 20, existing: [], focusX: 0.5, focusY: 0.5))
        XCTAssertNil(CineoCueCameraDirector.propose(cue: .init(at: 19, kind: .crescendo),
            videoDuration: 20, existing: [], focusX: 0.5, focusY: 0.5))
    }
}
