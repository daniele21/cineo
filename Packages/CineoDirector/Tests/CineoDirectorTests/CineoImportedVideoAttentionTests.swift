import Foundation
import Testing
import CineoEvents
import CineoScene
@testable import CineoDirector

struct CineoImportedVideoAttentionTests {
    private func sample(_ time: Double, _ x: Double, _ y: Double,
                        _ confidence: Double = 0.95) -> CineoImportedPointerSample {
        .init(sourceSeconds: time, x: x, y: y, confidence: confidence)
    }

    @Test func rejectsCorruptAndUnorderedDetections() throws {
        #expect(throws: CineoImportedVideoError.invalidAnalysis) {
            try CineoImportedPointerAnalysis(sourceDuration: 10, seedSourceSeconds: 0,
                 samples: [sample(2, 0.5, 0.5), sample(1, 0.5, 0.5)])
        }
        #expect(throws: CineoImportedVideoError.invalidAnalysis) {
            try CineoImportedPointerAnalysis(sourceDuration: 10, seedSourceSeconds: 0,
                 samples: [sample(1, 2, 0.5)])
        }
    }

    @Test func videoDetectionsNeverBecomeClicksOrOverlaySidecars() throws {
        let report = try CineoImportedPointerAnalysis(sourceDuration: 10, seedSourceSeconds: 0,
               samples: [sample(0, 0.2, 0.3), sample(0.2, 0.4, 0.5, 0.3),
                         sample(0.4, 0.6, 0.8)])
        let events = report.movementEvents()
        #expect(events.count == 2)
        #expect(events.allSatisfy { $0.kind == .moved })
        #expect(report.provenance == "vision-manual-seed")
        #expect(events[0].sourceSeconds == 0)
        #expect(events[1].sourceSeconds == 0.4)
    }

    @Test func stableHighConfidencePointerCreatesEditableNonclickZoom() throws {
        let samples = (0...24).map { sample(Double($0) * 0.1, 0.78, 0.28) }
        let report = try CineoImportedPointerAnalysis(sourceDuration: 10,
                                                      seedSourceSeconds: 0, samples: samples)
        let planner = CineoImportedVideoAttentionPlanner()
        let dwells = planner.inferredDwells(analysis: report)
        #expect(dwells.count == 1)
        #expect(dwells[0].kind == .dwell)
        let proposal = planner.propose(analysis: report, outputDuration: 10,
                                      cutMapper: { $0 })
        #expect(proposal.shots.count == 1)
        #expect(proposal.shots[0].reason == .dwell)
        #expect(proposal.keyframes.count == 4)
        let scene = CineoScenePlan(outputWidth: 1920, outputHeight: 1080,
                                   camera: proposal.keyframes)
        try scene.validate()
    }

    @Test func gapsAndLowConfidenceDoNotCreateFalseAttention() throws {
        let report = try CineoImportedPointerAnalysis(sourceDuration: 10, seedSourceSeconds: 0,
                 samples: [sample(0, 0.4, 0.4), sample(0.2, 0.4, 0.4),
                           sample(0.4, 0.4, 0.4, 0.2), sample(1.2, 0.4, 0.4),
                           sample(1.4, 0.4, 0.4)])
        #expect(CineoImportedVideoAttentionPlanner().inferredDwells(analysis: report).isEmpty)
    }

    @Test func cutMappingRemovesExcludedDwellsAndRetimesRemaining() throws {
        let entries = (0...12).map { sample(Double($0) * 0.1, 0.7, 0.25) } +
            (30...42).map { sample(Double($0) * 0.1, 0.27, 0.7) }
        let report = try CineoImportedPointerAnalysis(sourceDuration: 10,
                                                      seedSourceSeconds: 0, samples: entries)
        let planner = CineoImportedVideoAttentionPlanner()
        let p = planner.propose(analysis: report, outputDuration: 8, cutMapper: { time in
            if time < 2 { return nil }
            return time - 2
        })
        #expect(p.shots.count == 1)
        #expect(p.shots[0].focusX < 0.5)
        #expect(p.keyframes.allSatisfy { $0.time < 8 })
    }

    @Test func bidirectionalTracesMergeInSourceOrderWithoutInventedSamples() throws {
        let before = try CineoImportedPointerAnalysis(
            sourceDuration: 20, seedSourceSeconds: 8,
            samples: [sample(6, 0.2, 0.2), sample(7, 0.4, 0.3),
                      sample(8, 0.5, 0.5, 0.7)])
        let after = try CineoImportedPointerAnalysis(
            sourceDuration: 20, seedSourceSeconds: 8,
            samples: [sample(8, 0.5, 0.5, 0.95), sample(9, 0.6, 0.4),
                      sample(11, 0.7, 0.3)])
        let merged = try before.merging(after)
        #expect(merged.samples.map(\.sourceSeconds) == [6, 7, 8, 9, 11])
        #expect(merged.samples[2].confidence == 0.95)
        #expect(merged.movementEvents().count == 5)
        #expect(merged.movementEvents().allSatisfy { $0.kind == .moved })
        #expect(CineoImportedVideoAttentionPlanner().inferredDwells(analysis: merged).isEmpty)
    }

    @Test func rejectsMergeAcrossDifferentSourceDurations() throws {
        let one = try CineoImportedPointerAnalysis(
            sourceDuration: 10, seedSourceSeconds: 0,
            samples: [sample(0, 0.5, 0.5)])
        let other = try CineoImportedPointerAnalysis(
            sourceDuration: 20, seedSourceSeconds: 0,
            samples: [sample(0, 0.5, 0.5)])
        #expect(throws: CineoImportedVideoError.invalidAnalysis) {
            try one.merging(other)
        }
    }

    @Test func JSONRoundTripPreservesProvenanceAndBounds() throws {
        let input = try CineoImportedPointerAnalysis(
            sourceDuration: 10, seedSourceSeconds: 1,
            samples: [sample(1, 0.5, 0.5), sample(1.2, 0.52, 0.51)])
        let data = try JSONEncoder().encode(input)
        let restored = try JSONDecoder().decode(CineoImportedPointerAnalysis.self, from: data)
        try restored.validate()
        #expect(input == restored)
    }
}
