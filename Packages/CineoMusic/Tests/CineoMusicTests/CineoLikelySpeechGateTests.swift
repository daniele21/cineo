import XCTest
@testable import CineoMusic

final class CineoLikelySpeechGateTests: XCTestCase {
    func testVoiceWindowsFilterSystemNotificationWithoutLosingQuietGaps() {
        let activity = [
            CineoAudioActivityRange(start: 1, end: 1.3),
            CineoAudioActivityRange(start: 3, end: 4.2),
            CineoAudioActivityRange(start: 4.8, end: 5.4)
        ]
        let allowed = [CineoAudioActivityRange(start: 2.9, end: 5.5)]
        let result = CineoLikelySpeechGate.intersection(activity: activity,
                                                         speechWindows: allowed)
        XCTAssertEqual(result.count, 2)
        XCTAssertEqual(result[0].start, 3, accuracy: 1e-9)
        XCTAssertEqual(result[0].end, 4.2, accuracy: 1e-9)
        XCTAssertEqual(result[1].start, 4.8, accuracy: 1e-9)
        XCTAssertEqual(result[1].end, 5.4, accuracy: 1e-9)
    }
    func testAbsentSpeechLabelsNeverInventNarration() {
        let activity = [CineoAudioActivityRange(start: 0, end: 2)]
        XCTAssertTrue(CineoLikelySpeechGate.intersection(
            activity: activity, speechWindows: []).isEmpty)
    }
    func testLegacyDuckingSettingsRemainsCompatible() throws {
        let json = Data(#"{"enabled":true,"level":0.25,"threshold":0.08,"attack":0.2,"release":0.55}"#.utf8)
        let decoded = try JSONDecoder().decode(CineoDuckingSettings.self, from: json)
        XCTAssertNil(decoded.detectionMode)
        XCTAssertTrue(decoded.enabled)
    }
}
