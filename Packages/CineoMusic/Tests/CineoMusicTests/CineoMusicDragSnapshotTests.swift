import XCTest
@testable import CineoMusic

final class CineoMusicDragSnapshotTests: XCTestCase {
    func testMoveOnlyChangesOffsetAndClampsAtVideoEnd() throws {
        let first = CineoMusicDragSnapshot(
            offset: 2, clip: .init(sourceIn: 1, duration: 3),
            sourceDuration: 10, videoDuration: 15)
        let result = try XCTUnwrap(first.edit(handle: .move, deltaSeconds: 1.5))
        XCTAssertEqual(result.offset, 3.5)
        XCTAssertEqual(result.clip.sourceIn, 1)
        XCTAssertEqual(result.clip.duration, 3)
    }

    func testTrimStartPreservesEndAndMovesSourceClock() throws {
        let first = CineoMusicDragSnapshot(
            offset: 2, clip: .init(sourceIn: 1, duration: 7),
            sourceDuration: 12, videoDuration: 20)
        let after = try XCTUnwrap(first.edit(handle: .trimStart, deltaSeconds: 1.25))
        XCTAssertEqual(after.offset, 3.25, accuracy: 1e-9)
        XCTAssertEqual(after.clip.sourceIn, 2.25, accuracy: 1e-9)
        XCTAssertEqual(after.clip.duration ?? -1, 5.75, accuracy: 1e-9)
        XCTAssertEqual(after.offset + (after.clip.duration ?? 0), 9, accuracy: 1e-9)
    }

    func testTrimEndCannotRunBeyondSourceUnlessLooping() throws {
        let linear = CineoMusicDragSnapshot(offset: 1,
            clip: .init(sourceIn: 4, duration: 2),
            sourceDuration: 7, videoDuration: 30)
        XCTAssertEqual(linear.edit(handle: .trimEnd, deltaSeconds: 20)?.clip.duration, 3)
        let looping = CineoMusicDragSnapshot(offset: 1,
            clip: .init(sourceIn: 4, duration: 2, loop: true, loopCrossfade: 0.2),
            sourceDuration: 7, videoDuration: 30)
        XCTAssertEqual(looping.edit(handle: .trimEnd, deltaSeconds: 20)?.clip.duration, 22)
    }

    func testHandlesAndInvalidGeometry() {
        let snapshot = CineoMusicDragSnapshot(offset: 2,
            clip: .init(sourceIn: 0, duration: 5),
            sourceDuration: 10, videoDuration: 20)
        XCTAssertEqual(snapshot.selectedHandle(touchX: 20, timelineWidth: 200), .trimStart)
        XCTAssertEqual(snapshot.selectedHandle(touchX: 70, timelineWidth: 200), .trimEnd)
        XCTAssertEqual(snapshot.selectedHandle(touchX: 40, timelineWidth: 200), .move)
        XCTAssertNil(snapshot.edit(handle: .move, deltaSeconds: .nan))
    }
}
