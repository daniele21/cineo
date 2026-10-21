import Foundation
import XCTest
@testable import CineoMusic

final class CineoMusicBeatSyncTests: XCTestCase {
    func testLoopedClipSegmentsRespectVideoBoundsAndTrim() throws {
        let clip = CineoMusicClip(sourceIn: 2, duration: 14, loop: true)
        let segments = try clip.segments(sourceDuration: 7, videoDuration: 20, offset: 3)
        XCTAssertEqual(segments.map(\.duration), [5, 5, 4])
        XCTAssertEqual(segments.map(\.timelineStart), [3, 8, 13])
        XCTAssertEqual(segments.map(\.sourceStart), [2, 2, 2])
        XCTAssertEqual(clip.playbackPosition(videoTime: 9, sourceDuration: 7,
                                             videoDuration: 20, offset: 3), 3)
    }

    func testNoLoopDoesNotExtendPastSourceOrVideo() throws {
        let clip = CineoMusicClip(sourceIn: 2, duration: 30)
        XCTAssertEqual(try clip.segments(sourceDuration: 8, videoDuration: 10, offset: 3)
            .map(\.duration), [6])
        XCTAssertNil(clip.playbackPosition(videoTime: 9.01, sourceDuration: 8,
                                           videoDuration: 10, offset: 3))
        XCTAssertThrowsError(try CineoMusicClip(sourceIn: 10)
            .segments(sourceDuration: 8, videoDuration: 20, offset: 0))
    }

    func testSilenceHasNoInventedBeats() {
        let result = CineoBeatAnalyzer.analyze(samples: [Float](repeating: 0, count: 22050),
                                               sampleRate: 11025)
        XCTAssertEqual(result.onsets, [])
        XCTAssertNil(result.estimatedBPM)
        XCTAssertTrue(result.waveform.allSatisfy { $0 == 0 })
    }

    func testPulseTrainDetectedWithoutBpmHint() {
        let rate = 11025.0
        var samples = [Float](repeating: 0, count: Int(rate * 6))
        for pulse in 1...9 {
            let start = Int(Double(pulse) * 0.5 * rate)
            for k in 0..<180 {
                samples[start + k] = Float(0.9 * exp(-Double(k) / 60)) *
                    (k.isMultiple(of: 2) ? 1 : -1)
            }
        }
        let analysis = CineoBeatAnalyzer.analyze(samples: samples, sampleRate: rate)
        for pulse in 1...9 {
            let t = Double(pulse) * 0.5
            XCTAssertTrue(analysis.onsets.contains { abs($0 - t) < 0.075 },
                          "Missing pulse at \(t): \(analysis.onsets)")
        }
    }

    func testExplicitConfirmationCandidateRejectsCrowdedKeyframes() {
        let keys = [
            CineoBeatKeyframe(time: 0.2, zoom: 1),
            CineoBeatKeyframe(time: 2.13, zoom: 1.5),
            CineoBeatKeyframe(time: 3, zoom: 1.5)
        ]
        let clip = CineoMusicClip()
        let aligned = CineoBeatSync.propose(keyframes: keys, playhead: 2.1,
                                            onsetSeconds: [1, 2, 2.5],
                                            clip: clip, sourceDuration: 8,
                                            videoDuration: 8, offset: 0)
        XCTAssertEqual(aligned?.keyframeIndex, 1)
        XCTAssertEqual(aligned?.from, 2.13)
        XCTAssertEqual(aligned?.to, 2)
        XCTAssertNil(CineoBeatSync.propose(keyframes: keys, playhead: 2.1,
                                           onsetSeconds: [2.95],
                                           clip: clip, sourceDuration: 8,
                                           videoDuration: 8, offset: 0))
    }

    func testBeatSyncIncludesLoopOffsetAndClipSourceIn() {
        let keys = [CineoBeatKeyframe(time: 11.06, zoom: 1.5)]
        let clip = CineoMusicClip(sourceIn: 1, duration: 16, loop: true)
        let candidate = CineoBeatSync.propose(keyframes: keys, playhead: 11.06,
                                              onsetSeconds: [1.5],
                                              clip: clip, sourceDuration: 5,
                                              videoDuration: 25, offset: 2)
        XCTAssertEqual(candidate?.to ?? -1, 10.5, accuracy: 0.0001)
    }
}
