import Testing
@testable import CineoVideoAnalysis

struct CineoVisualChangeTests {
    let width = CineoVisualChangeDetector.width
    let height = CineoVisualChangeDetector.height

    @Test func unchangedFramesAndCompressionNoiseProduceNoCue() {
        let blank = [UInt8](repeating: 120, count: width * height)
        let noise = [UInt8](repeating: 130, count: width * height)
        #expect(CineoVisualChangeDetector().detect(
            previous: blank, current: blank, sourceSeconds: 1) == nil)
        #expect(CineoVisualChangeDetector().detect(
            previous: blank, current: noise, sourceSeconds: 1) == nil)
    }

    @Test func localizedUIChangeProducesQualifiedTarget() {
        let original = [UInt8](repeating: 120, count: width * height)
        var modified = original
        for y in 12..<22 {
            for x in 40..<54 { modified[y * width + x] = 230 }
        }
        let cue = CineoVisualChangeDetector().detect(
            previous: original, current: modified, sourceSeconds: 5)
        #expect(cue != nil)
        #expect((cue?.x ?? 0) > 0.5)
        #expect((cue?.changedFraction ?? 0) > 0.2)
        #expect((cue?.confidence ?? 0) >= 0.78)
    }

    @Test func fullScreenFlashIsRejected() {
        let black = [UInt8](repeating: 0, count: width * height)
        let white = [UInt8](repeating: 255, count: width * height)
        #expect(CineoVisualChangeDetector().detect(
            previous: black, current: white, sourceSeconds: 2) == nil)
    }

    @Test func badFrameSizesAndInvalidTimeAreRejected() {
        let frame = [UInt8](repeating: 0, count: width * height)
        #expect(CineoVisualChangeDetector().detect(
            previous: [], current: frame, sourceSeconds: 1) == nil)
        #expect(CineoVisualChangeDetector().detect(
            previous: frame, current: frame, sourceSeconds: .nan) == nil)
    }
}
