import Foundation
import XCTest
@testable import CineoMusic

final class CineoAudioActivityPrecisionTests: XCTestCase {
    func testTwentyMillisecondRMSDistinguishesSpeechSizedRegionsAndSilence() {
        let rate = 2_000.0
        let length = 10.0
        let samples: [Float] = (0..<Int(rate * length)).map { i in
            let t = Double(i) / rate
            let active = (t >= 2 && t < 3.05) || (t >= 5.1 && t < 6.0)
            let click = t >= 7.2 && t < 7.23
            return (active || click) ? Float(0.55 * sin(t * 2 * .pi * 240)) : 0
        }
        let analysis = CineoBeatAnalyzer.analyze(samples: samples, sampleRate: rate)
        XCTAssertGreaterThan(analysis.activityLevels.count, analysis.waveform.count)
        XCTAssertGreaterThan(analysis.activityLevels.count, 400)
        let ranges = CineoAudioActivityDetector.ranges(
            peakBins: analysis.activityLevels,
            duration: analysis.sourceDuration, threshold: 0.08)
        XCTAssertEqual(ranges.count, 2, "\(ranges)")
        XCTAssertEqual(ranges[0].start, 2, accuracy: 0.08)
        XCTAssertEqual(ranges[0].end, 3.05, accuracy: 0.10)
        XCTAssertEqual(ranges[1].start, 5.1, accuracy: 0.08)
        XCTAssertEqual(ranges[1].end, 6.0, accuracy: 0.10)
    }

    func testSilentMusicHasNoFictitiousAudioActivity() {
        let analysis = CineoBeatAnalyzer.analyze(
            samples: [Float](repeating: 0, count: 5000), sampleRate: 1000)
        XCTAssertTrue(analysis.activityLevels.allSatisfy { $0 == 0 })
        XCTAssertTrue(CineoAudioActivityDetector.ranges(
            peakBins: analysis.activityLevels, duration: 5, threshold: 0.08).isEmpty)
    }
}
