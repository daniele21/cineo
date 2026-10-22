import Foundation
import XCTest
@testable import CineoMusic

final class CineoACERepaintTests: XCTestCase {
    func testDocumentedRepaintPayload() throws {
        let r = CineoACERepaintRequest(sourceStart: 10, sourceEnd: 25,
                    sourceDuration: 40, prompt: "Soft jazz electric piano", seed: 7)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: r.jsonBody()) as? [String: Any])
        XCTAssertEqual(json["task_type"] as? String, "repaint")
        XCTAssertEqual(json["repainting_start"] as? Double, 10)
        XCTAssertEqual(json["repainting_end"] as? Double, 25)
        XCTAssertEqual(json["lyrics"] as? String, "[Instrumental]")
        XCTAssertEqual(json["output_format"] as? String, "wav16")
    }

    func testInvalidSpanOrNoPromptNeverSubmitted() {
        XCTAssertThrowsError(try CineoACERepaintRequest(
            sourceStart: 10, sourceEnd: 10.5, sourceDuration: 30, prompt: "Music").validate())
        XCTAssertThrowsError(try CineoACERepaintRequest(
            sourceStart: 29, sourceEnd: 31, sourceDuration: 30, prompt: "Music").validate())
        XCTAssertThrowsError(try CineoACERepaintRequest(
            sourceStart: 3, sourceEnd: 7, sourceDuration: 30, prompt: "").validate())
    }

    func testMultipartUsesBackendFieldNamesAndPreservesBinary() throws {
        let request = CineoACERepaintRequest(sourceStart: 1, sourceEnd: 4,
                                             sourceDuration: 10, prompt: "ambient")
        let sample = Data([0, 0, 255, 13, 10, 0, 254])
        let result = try CineoACEMultipartRepaint.make(request: request,
            source: sample, extension: "wav", boundary: "cineo_boundary_1234")
        XCTAssertNotNil(result.range(of: Data("name=\"request\"".utf8)))
        XCTAssertNotNil(result.range(of: Data("name=\"audio\"".utf8)))
        XCTAssertNotNil(result.range(of: sample))
        XCTAssertTrue(result.suffix(25).contains(45))
    }

    func testSelectVideoTimeRejectsLoopCrossing() throws {
        let clip = CineoMusicClip(sourceIn: 0, duration: 14, loop: true, loopCrossfade: 0)
        XCTAssertThrowsError(try CineoACERepaintRequest.fromVideoSelection(
            start: 3, end: 8, clip: clip, offset: 1,
            sourceDuration: 6, videoDuration: 20, prompt: "Soft strings", seed: 42))
        let r = try CineoACERepaintRequest.fromVideoSelection(
            start: 2, end: 4, clip: clip, offset: 1,
            sourceDuration: 6, videoDuration: 20, prompt: "Soft strings", seed: 42)
        XCTAssertEqual(r.sourceStart, 1, accuracy: 0.0001)
        XCTAssertEqual(r.sourceEnd, 3, accuracy: 0.0001)
    }
}
