import Testing
@testable import CineoDirector

struct CineoImportedAssistedPlannerTests {
    private func cue(_ t: Double, _ x: Double = 0.4, _ confidence: Double = 0.93,
                     _ changed: Double = 0.3) -> CineoVisualAttentionCue {
        .init(sourceSeconds: t, x: x, y: 0.4,
              confidence: confidence, changedFraction: changed)
    }

    @Test func cursorlessVideoCanSuggestStrongVisibleChange() {
        let result = CineoImportedAssistedPlanner().propose(
            pointerAnalysis: nil, visualCues: [cue(6)],
            outputDuration: 15, cutMapper: { $0 })
        #expect(result.proposal.shots.count == 1)
        #expect(result.evidence[0].origin == .visualChange)
        #expect(result.evidence[0].confidence < 1)
        #expect(result.proposal.shots[0].reason == .dwell)
    }

    @Test func weakOrInvalidPixelDifferencesCannotFabricateZooms() {
        let result = CineoImportedAssistedPlanner().propose(
            pointerAnalysis: nil,
            visualCues: [cue(2, 0.4, 0.3), cue(4, 0.4, 0.95, 0.03),
                         cue(.nan), cue(20)],
            outputDuration: 10, cutMapper: { $0 })
        #expect(result.proposal.shots.isEmpty)
    }

    @Test func correlatedPointerAndVisualCueProduceOneHigherConfidenceSuggestion() throws {
        let samples = (0...12).map {
            CineoImportedPointerSample(sourceSeconds: 5 + Double($0) * 0.1,
                                       x: 0.42, y: 0.4, confidence: 0.95)
        }
        let pointer = try CineoImportedPointerAnalysis(
            sourceDuration: 20, seedSourceSeconds: 5, samples: samples)
        let result = CineoImportedAssistedPlanner().propose(
            pointerAnalysis: pointer, visualCues: [cue(5.6, 0.43)],
            outputDuration: 20, cutMapper: { $0 })
        #expect(result.proposal.shots.count == 1)
        #expect(result.evidence[0].origin == .correlated)
        #expect(result.evidence[0].confidence > 0.9)
    }

    @Test func cutsDropDeletedVisualRegionsAndRetainOtherIntervals() {
        let result = CineoImportedAssistedPlanner().propose(
            pointerAnalysis: nil, visualCues: [cue(1), cue(7)],
            outputDuration: 8,
            cutMapper: { $0 < 4 ? nil : $0 - 4 })
        #expect(result.proposal.shots.count == 1)
        #expect(result.proposal.shots[0].start < 4)
        #expect(result.proposal.keyframes.allSatisfy { $0.time <= 8 })
    }

    @Test func suggestionsSpanWholeOutputTimelineIndependentOfSelection() {
        let result = CineoImportedAssistedPlanner().propose(
            pointerAnalysis: nil,
            visualCues: [cue(3, 0.2), cue(28, 0.6), cue(55, 0.8)],
            outputDuration: 65, cutMapper: { $0 })
        #expect(result.proposal.shots.count == 3)
        #expect(result.proposal.shots[0].start < 10)
        #expect(result.proposal.shots[1].start > 20)
        #expect(result.proposal.shots[2].start > 45)
    }
}
