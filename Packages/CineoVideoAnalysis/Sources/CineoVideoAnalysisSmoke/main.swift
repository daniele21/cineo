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

        // CLT-compatible pixel-difference regression: no Testing module
        // is available under /Library/Developer/CommandLineTools.
        let detector = CineoVisualChangeDetector()
        let width = CineoVisualChangeDetector.width
        let height = CineoVisualChangeDetector.height
        let blank = [UInt8](repeating: 120, count: width * height)
        let noise = [UInt8](repeating: 130, count: width * height)
        guard detector.detect(previous: blank, current: blank,
                              sourceSeconds: 1) == nil,
              detector.detect(previous: blank, current: noise,
                              sourceSeconds: 1) == nil
        else { throw SmokeError.unexpectedResult }
        var changed = blank
        for y in 12..<22 {
            for x in 40..<54 { changed[y * width + x] = 230 }
        }
        guard let cue = detector.detect(
            previous: blank, current: changed, sourceSeconds: 3),
              cue.x > 0.5, cue.confidence >= 0.78
        else { throw SmokeError.unexpectedResult }
        let white = [UInt8](repeating: 255, count: width * height)
        guard detector.detect(previous: blank, current: white,
                              sourceSeconds: 4) == nil
        else { throw SmokeError.unexpectedResult }
        print("PASS: native CLT visual-change, compression-noise and flash gates")

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
