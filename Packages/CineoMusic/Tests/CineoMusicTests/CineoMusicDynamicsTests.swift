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

    func testCueAndSettingsRejectInvalidValues() {
        XCTAssertNoThrow(try CineoMusicCue(time: 2).validate(videoDuration: 3))
        XCTAssertThrowsError(try CineoMusicCue(time: 3).validate(videoDuration: 3))
        XCTAssertThrowsError(try CineoDuckingSettings(quietVolume: 2).validate())
    }
}
