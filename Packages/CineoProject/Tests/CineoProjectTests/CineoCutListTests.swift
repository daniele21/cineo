import Foundation
import Testing
@testable import CineoProject

struct CineoCutListTests {
    @Test func emptyCutPlanIsAnIdentityMapper() throws {
        let cuts = try CineoCutList(sourceDuration: 30)
        #expect(cuts.outputDuration == 30)
        #expect(cuts.sourceTime(at: 8.2) == 8.2)
        #expect(cuts.sourceTime(at: 30) == nil)
        #expect(cuts.outputTime(forSourceSeconds: 30) == nil)
    }

    @Test func removingMiddleIntervalIsNonDestructiveAndKeepsTimestamps() throws {
        let original = try CineoCutList(sourceDuration: 20)
        let cut = try original.removingSourceRange(start: 5, end: 10)
        #expect(original.outputDuration == 20)
        #expect(cut.outputDuration == 15)
        #expect(cut.retained == [.init(start: 0, end: 5),
                                  .init(start: 10, end: 20)])
        #expect(cut.sourceTime(at: 5) == 10)
        #expect(cut.sourceTime(at: 14.5) == 19.5)
        #expect(cut.outputTime(forSourceSeconds: 6) == nil)
        #expect(cut.outputTime(forSourceSeconds: 10) == 5)
    }

    @Test func multipleCutsInOutputTimeRetainOriginalSourceMapping() throws {
        let initial = try CineoCutList(sourceDuration: 20)
        let first = try initial.removingOutputRange(start: 5, end: 10)
        let second = try first.removingOutputRange(start: 3, end: 7)
        #expect(second.retained == [.init(start: 0, end: 3),
                                     .init(start: 12, end: 20)])
        #expect(second.outputDuration == 11)
        #expect(second.sourceTime(at: 3) == 12)
        #expect(second.nextRetainedSourceTime(after: 5.1) == 12)
        #expect(second.nextRetainedSourceTime(after: 20) == nil)
    }

    @Test func originalAudioActivityIsSplitAndRetimedByCuts() throws {
        let cuts = try CineoCutList(sourceDuration: 20)
            .removingOutputRange(start: 6, end: 12)
        #expect(cuts.outputRanges(overlappingSourceStart: 5, end: 14) ==
                [.init(start: 5, end: 6), .init(start: 6, end: 8)])
        #expect(cuts.outputRanges(overlappingSourceStart: 7, end: 10).isEmpty)
    }

    @Test func overlappingCutsDoNotCreateOverlappingOutput() throws {
        let original = try CineoCutList(sourceDuration: 20)
        let a = try original.removingSourceRange(start: 4, end: 8)
        let b = try a.removingSourceRange(start: 7, end: 12)
        #expect(b.retained == [.init(start: 0, end: 4),
                                .init(start: 12, end: 20)])
        #expect(b.outputDuration == 12)
        let encoded = try JSONEncoder().encode(b)
        #expect(try JSONDecoder().decode(CineoCutList.self, from: encoded) == b)
    }

    @Test func preventsEmptySourceAndInvalidTimeFromChangingCutList() throws {
        let original = try CineoCutList(sourceDuration: 10)
        #expect(throws: CineoCutError.emptyTimeline) {
            try original.removingSourceRange(start: 0, end: 10)
        }
        #expect(throws: CineoCutError.invalidRange) {
            try original.removingSourceRange(start: .nan, end: 3)
        }
        #expect(original.outputDuration == 10)
    }

    @Test func preservesFrameAlignedReversibleTimestamps() throws {
        let c = try CineoCutList(sourceDuration: 12).removingSourceRange(start: 3, end: 7)
        for time in [0.0, 1.0, 2.99, 7.0, 8.25, 11.99] {
            let output = try #require(c.outputTime(forSourceSeconds: time))
            #expect(abs((c.sourceTime(at: output) ?? -1) - time) < 1e-8)
        }
    }
}
