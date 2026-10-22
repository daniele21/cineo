import Testing
import CineoEvents
import CineoScene
@testable import CineoDirector

struct CineoCameraQualityTests {
    @Test func selectingShotsRebuildsSameDeterministicFrames() throws {
        let sidecar = try CineoPointerSidecar(events: [
            .init(sourceSeconds: 2, x: 0.2, y: 0.35, kind: .leftClick),
            .init(sourceSeconds: 8, x: 0.8, y: 0.7, kind: .leftClick)
        ])
        let director = CineoAutoEditPlanner()
        let proposal = director.propose(sidecar: sidecar, duration: 15)
        #expect(proposal.keyframes == director.keyframes(for: proposal.shots, duration: 15))
        #expect(director.keyframes(for: [], duration: 15).isEmpty)
        let selected = director.keyframes(for: [proposal.shots[1]], duration: 15)
        #expect(selected.count == 4)
        #expect(selected[0].time > 7)
        try CineoScenePlan(outputWidth: 1920, outputHeight: 1080,
                           camera: selected).validate()
    }

    @Test func conservativeSafetyMetricsFlagOverlapsAndUnsafeCrop() throws {
        let sidecar = try CineoPointerSidecar(events: [
            .init(sourceSeconds: 1.0, x: 0.03, y: 0.04, kind: .leftClick),
            .init(sourceSeconds: 6, x: 0.9, y: 0.9, kind: .rightClick)
        ])
        let proposal = CineoAutoEditPlanner().propose(sidecar: sidecar, duration: 12)
        let result = CineoCameraQuality.measure(shots: proposal.shots, duration: 12)
        #expect(result.isStructurallySafe)
        #expect(result.maximumZoom > 1)
        let first = proposal.shots[0]
        let duplicated = CineoCameraQuality.measure(shots: [first, first], duration: 12)
        #expect(!duplicated.isStructurallySafe)
    }
}
