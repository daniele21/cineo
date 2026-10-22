import Foundation
import XCTest
@testable import CineoMusic

final class CineoMusicPolishTests: XCTestCase {
    func testExistingMusicStateWithoutCrossfadeStillDecodes() throws {
        let old = #"{"sourceIn":1,"duration":12,"loop":true}"#
        let clip = try JSONDecoder().decode(CineoMusicClip.self, from: Data(old.utf8))
        XCTAssertEqual(clip.loopCrossfade, 0)
        XCTAssertEqual(clip.sourceIn, 1)
        XCTAssertEqual(clip.duration, 12)
    }

    func testCrossfadeUsesTwoOverlappingLayersWithNormalizedGains() throws {
        let clip = CineoMusicClip(sourceIn: 2, duration: 11, loop: true, loopCrossfade: 0.5)
        let segments = try clip.segments(sourceDuration: 7, videoDuration: 18, offset: 3)
        XCTAssertEqual(segments.map(\.timelineStart), [3, 7.5, 12])
        XCTAssertEqual(segments.map(\.duration), [5, 5, 2])
        let layers = clip.previewLayers(videoTime: 7.75, sourceDuration: 7,
                                         videoDuration: 18, offset: 3)
        XCTAssertEqual(layers.count, 2)
        XCTAssertEqual(layers.map(\.gain).reduce(0, +), 1, accuracy: 1e-9)
        XCTAssertEqual(layers[0].gain, 0.5, accuracy: 1e-9)
        XCTAssertEqual(layers[1].gain, 0.5, accuracy: 1e-9)
        XCTAssertEqual(layers[1].sourcePosition, 2.25, accuracy: 1e-9)
    }

    func testRejectInvalidCrossfadeAndNoLoopCompatibility() throws {
        XCTAssertThrowsError(try CineoMusicClip(sourceIn: 0, loop: true, loopCrossfade: 3)
            .segments(sourceDuration: 5, videoDuration: 10, offset: 0))
        XCTAssertThrowsError(try CineoMusicClip(sourceIn: 1, loop: true, loopCrossfade: 2)
            .segments(sourceDuration: 4, videoDuration: 10, offset: 0))
        let hard = CineoMusicClip(sourceIn: 0, duration: 10, loop: true)
        XCTAssertEqual(try hard.segments(sourceDuration: 4, videoDuration: 10, offset: 0)
            .map(\.timelineStart), [0, 4, 8])
    }

    func testDuckingEnvelopeAndSilence() throws {
        let settings = CineoDuckingSettings(enabled: true, level: 0.2, threshold: 0.08,
                                           attack: 0.5, release: 0.5)
        try settings.validate()
        let regions = [CineoAudioActivityRange(start: 2, end: 4)]
        XCTAssertEqual(settings.gain(at: 0, activeRanges: regions), 1)
        XCTAssertEqual(settings.gain(at: 1.75, activeRanges: regions), 0.6, accuracy: 1e-9)
        XCTAssertEqual(settings.gain(at: 3, activeRanges: regions), 0.2, accuracy: 1e-9)
        XCTAssertEqual(settings.gain(at: 4.25, activeRanges: regions), 0.6, accuracy: 1e-9)
        XCTAssertEqual(settings.gain(at: 5, activeRanges: regions), 1)
        XCTAssertEqual(settings.envelopePoints(activeRanges: regions, clipStart: 0, clipEnd: 6)
            .map(\.time), [0, 1.5, 2, 4, 4.5, 6])
        XCTAssertEqual(CineoDuckingSettings(enabled: false)
            .gain(at: 3, activeRanges: regions), 1)
    }

    func testActivityDetectorIgnoresBriefClickAndMergesCloseActivity() {
        let peaks: [Float] = [0,0,0.2,0.1,0.15,0,0.12,0.1,0.1,0,0,0]
        let detected = CineoAudioActivityDetector.ranges(
            peakBins: peaks, duration: 6, threshold: 0.08)
        XCTAssertEqual(detected, [
            CineoAudioActivityRange(start: 1, end: 2.5),
            CineoAudioActivityRange(start: 3, end: 4.5)
        ])
        XCTAssertTrue(CineoAudioActivityDetector.ranges(
            peakBins: [0,0,0,0], duration: 10, threshold: 0.1).isEmpty)
    }

    func testCueValidation() throws {
        XCTAssertNoThrow(try CineoMusicCue(at: 2, kind: .hit, label: "Click")
            .validate(videoDuration: 10))
        XCTAssertThrowsError(try CineoMusicCue(at: 11, kind: .transition)
            .validate(videoDuration: 10))
    }
}
