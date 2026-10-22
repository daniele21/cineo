import Foundation
import XCTest
@testable import CineoMusic

final class CineoMusicDynamicsTests: XCTestCase {
    func testSilenceDoesNotTriggerDucking() {
        let segments = CineoAudioDynamics.detectActivity(
            samples: [Float](repeating: 0, count: 16000 * 2), sampleRate: 16000)
        XCTAssertTrue(segments.isEmpty)
    }

    func testRmsActivityDetectionAndGapMerging() {
        let rate = 16000
        var s = [Float](repeating: 0, count: rate * 3)
        for i in Int(0.5 * Double(rate))..<Int(1.0 * Double(rate)) { s[i] = 0.3 }
        for i in Int(1.1 * Double(rate))..<Int(1.5 * Double(rate)) { s[i] = 0.3 }
        let activity = CineoAudioDynamics.detectActivity(samples: s, sampleRate: Double(rate))
        XCTAssertEqual(activity.count, 1)
        XCTAssertEqual(activity[0].start, 0.5, accuracy: 0.06)
        XCTAssertEqual(activity[0].end, 1.5, accuracy: 0.06)
    }

    func testDuckingAttackAndReleaseEnvelope() {
        let a = [CineoAudioActivity(start: 2, end: 3)]
        let s = CineoDuckingSettings(enabled: true, quietVolume: 0.2,
                                    attack: 0.2, release: 0.5)
        XCTAssertEqual(CineoAudioDynamics.gain(at: 1.0, activity: a, settings: s), 1)
        XCTAssertEqual(CineoAudioDynamics.gain(at: 1.9, activity: a, settings: s), 0.6, accuracy: 0.001)
        XCTAssertEqual(CineoAudioDynamics.gain(at: 2.5, activity: a, settings: s), 0.2)
        XCTAssertEqual(CineoAudioDynamics.gain(at: 3.25, activity: a, settings: s), 0.6, accuracy: 0.001)
        XCTAssertEqual(CineoAudioDynamics.gain(at: 4, activity: a, settings: s), 1)
    }

    func testAutomationCapturesNonLinearOverlapAndStaysBounded() {
        let a = [CineoAudioActivity(start: 1, end: 1.6)]
        let s = CineoDuckingSettings(enabled: true, quietVolume: 0.25)
        let points = CineoAudioDynamics.automation(start: 0, end: 3, settings: s, activity: a) {
            CineoAudioDynamics.gain(at: $0, activity: a, settings: s) *
                min(1, $0 / 0.5)
        }
        XCTAssertTrue(points.count >= 5 && points.count < 200)
        XCTAssertEqual(points.first?.gain ?? -1, 0, accuracy: 0.01)
        XCTAssertEqual(points.last?.gain ?? -1, 1, accuracy: 0.01)
    }

    func testCrossfadeTwoLaneTimingAndFadeInOut() throws {
        let clip = CineoMusicClip(sourceIn: 2, duration: 15, loop: true, crossfade: 1)
        let parts = try clip.arrangedSegments(sourceDuration: 8, videoDuration: 22, offset: 3)
        XCTAssertEqual(parts.map(\.timelineStart), [3, 8, 13])
        XCTAssertEqual(parts.map(\.lane), [0, 1, 0])
        XCTAssertEqual(parts.map(\.duration), [6, 6, 5])
        XCTAssertEqual(parts[0].fadeOut, 1)
        XCTAssertEqual(parts[1].fadeIn, 1)
        XCTAssertEqual(parts[1].fadeOut, 1)
        XCTAssertEqual(parts[2].fadeOut, 0)
        let atSeam = clip.sources(at: 8.5, sourceDuration: 8, videoDuration: 22, offset: 3)
        XCTAssertEqual(atSeam.count, 2)
        XCTAssertEqual(atSeam.map(\.gain).reduce(0,+), 1, accuracy: 0.01)
        XCTAssertThrowsError(try CineoMusicClip(loop: true, crossfade: 4)
           .arrangedSegments(sourceDuration: 8, videoDuration: 22, offset: 3))
    }

    func testOldClipJSONDecodesWithoutCrossfadeField() throws {
        let decoded = try JSONDecoder().decode(CineoMusicClip.self,
            from: Data(#"{"sourceIn":0,"duration":12,"loop":true}"#.utf8))
        XCTAssertNil(decoded.crossfade)
        XCTAssertEqual(try decoded.arrangedSegments(sourceDuration: 5,
                videoDuration: 15, offset: 0).count, 3)
    }

    func testManualCueAlignmentRequiresOrderedCameraPeak() {
        let keys = [CineoBeatKeyframe(time: 1, zoom: 1),
                    CineoBeatKeyframe(time: 2, zoom: 1.5),
                    CineoBeatKeyframe(time: 2.4, zoom: 1.5)]
        XCTAssertEqual(CineoBeatSync.proposeToTime(keyframes: keys, playhead: 2,
                                                    targetTime: 2.25)?.to, 2.25)
        XCTAssertNil(CineoBeatSync.proposeToTime(keyframes: keys, playhead: 2,
                                                 targetTime: 2.37))
    }

    func testCueAndSettingsRejectInvalidValues() {
        XCTAssertNoThrow(try CineoMusicCue(time: 2).validate(videoDuration: 3))
        XCTAssertThrowsError(try CineoMusicCue(time: 3).validate(videoDuration: 3))
        XCTAssertThrowsError(try CineoDuckingSettings(quietVolume: 2).validate())
    }
}
