import Foundation
import CineoDirector
import CineoVideoAnalysis

enum SmokeError: Error { case unexpectedResult }

@main
struct ImportedVideoNativeSmoke {
    static func main() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("cineo-import-video-smoke-\(UUID().uuidString)",
                                    isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let video = directory.appendingPathComponent("sample.mp4")
        try Data("test only; not a real movie".utf8).write(to: video)
        let report = try CineoImportedPointerAnalysis(
            sourceDuration: 10, seedSourceSeconds: 1,
            samples: [
                .init(sourceSeconds: 1, x: 0.3, y: 0.4, confidence: 1),
                .init(sourceSeconds: 1.2, x: 0.31, y: 0.4, confidence: 0.9),
                .init(sourceSeconds: 1.4, x: 0.32, y: 0.4, confidence: 0.8)
            ])
        let store = CineoImportedAnalysisStore()
        try store.save(report, forVideo: video)
        guard try store.load(forVideo: video) == report else { throw SmokeError.unexpectedResult }
        try Data("modified video bytes".utf8).write(to: video)
        if (try? store.load(forVideo: video)) != nil { throw SmokeError.unexpectedResult }

        let project = directory.appendingPathComponent("test.cineo", isDirectory: true)
        try FileManager.default.createDirectory(at: project, withIntermediateDirectories: true)
        try store.save(report, projectURL: project)
        guard try store.load(projectURL: project) == report else { throw SmokeError.unexpectedResult }

        // CLT-compatible deterministic visual-analysis gates. Apple's
        // standalone Command Line Tools do not ship Swift Testing.
        let visualDetector = CineoVisualChangeDetector()
        let width = CineoVisualChangeDetector.width
        let height = CineoVisualChangeDetector.height
        let baseline = [UInt8](repeating: 120, count: width * height)
        let softNoise = [UInt8](repeating: 130, count: width * height)
        guard visualDetector.detect(previous: baseline, current: baseline,
                                    sourceSeconds: 1) == nil,
              visualDetector.detect(previous: baseline, current: softNoise,
                                    sourceSeconds: 1) == nil
        else { throw SmokeError.unexpectedResult }
        var uiFrame = baseline
        for y in 12..<22 {
            for x in 40..<54 { uiFrame[y * width + x] = 230 }
        }
        guard let candidate = visualDetector.detect(
            previous: baseline, current: uiFrame, sourceSeconds: 3),
              candidate.x > 0.5,
              candidate.confidence >= 0.78,
              candidate.changedFraction >= 0.2
        else { throw SmokeError.unexpectedResult }
        let white = [UInt8](repeating: 255, count: width * height)
        guard visualDetector.detect(previous: baseline, current: white,
                                    sourceSeconds: 4) == nil,
              visualDetector.detect(previous: baseline, current: uiFrame,
                                    sourceSeconds: .nan) == nil
        else { throw SmokeError.unexpectedResult }

        let reportVisual = try CineoVisualChangeReport(
            sourceDuration: 10, changes: [candidate])
        let visualStore = CineoVisualChangeStore()
        try visualStore.save(reportVisual, forVideo: video)
        let cacheVisual = try visualStore.load(forVideo: video)
        guard cacheVisual.changes.count == 1,
              cacheVisual.changes[0] == candidate,
              cacheVisual.provenance == "pixel-ui-difference"
        else { throw SmokeError.unexpectedResult }
        try visualStore.save(reportVisual, projectURL: project)
        let projectVisual = try visualStore.load(projectURL: project)
        guard projectVisual.changes == [candidate] else {
            throw SmokeError.unexpectedResult
        }
        do {
            _ = try CineoVisualChangeReport(
                sourceDuration: 2, changes: [candidate])
            throw SmokeError.unexpectedResult
        } catch CineoVisualAnalysisError.invalidVideo {
            // Pixel-derived timestamps outside the source cannot be persisted.
        }
        try Data("another video revision".utf8).write(to: video)
        if (try? visualStore.load(forVideo: video)) != nil {
            throw SmokeError.unexpectedResult
        }
        print("PASS: CLT visual change/noise/flash gates, local cue cache invalidation and project persistence")

        let tracker = CineoVideoCursorTracker()
        do {
            _ = try await tracker.analyze(videoURL: video, expectedSourceDuration: 10,
                                           seedSourceSeconds: -1, hotspotX: 0.5, hotspotY: 0.5)
            throw SmokeError.unexpectedResult
        } catch CineoVideoTrackingError.invalidSelection {
            // The user must choose a valid seed before any AVFoundation decode.
        }
        print("PASS: native analysis cache fingerprint, .cineo round-trip and invalid-seed guard")
    }
}
