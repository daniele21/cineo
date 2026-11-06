import Foundation
import Testing
@testable import CineoVideoAnalysis

struct CineoVisualChangeStoreTests {
    @Test func projectReportRoundTripsWithoutSavingAnyFrameBytes() throws {
        let project = FileManager.default.temporaryDirectory
            .appendingPathComponent("cineo-visual-\(UUID().uuidString).cineo", isDirectory: true)
        try FileManager.default.createDirectory(at: project, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: project) }
        let cue = CineoVisualChangeCandidate(
            sourceSeconds: 3, x: 0.55, y: 0.3,
            confidence: 0.9, changedFraction: 0.4)
        let report = try CineoVisualChangeReport(sourceDuration: 12, changes: [cue])
        let store = CineoVisualChangeStore()
        try store.save(report, projectURL: project)
        let loaded = try store.load(projectURL: project)
        #expect(loaded.sourceDuration == 12)
        #expect(loaded.provenance == "pixel-ui-difference")
        #expect(loaded.changes == [cue])
    }

    @Test func outOfRangeAndUnorderedPixelCuesAreRejected() {
        let later = CineoVisualChangeCandidate(
            sourceSeconds: 7, x: 0.5, y: 0.4,
            confidence: 0.9, changedFraction: 0.4)
        let earlier = CineoVisualChangeCandidate(
            sourceSeconds: 3, x: 0.5, y: 0.4,
            confidence: 0.9, changedFraction: 0.4)
        #expect(throws: CineoVisualAnalysisError.self) {
            try CineoVisualChangeReport(sourceDuration: 5, changes: [later])
        }
        #expect(throws: CineoVisualAnalysisError.self) {
            try CineoVisualChangeReport(sourceDuration: 10, changes: [later, earlier])
        }
    }
}
