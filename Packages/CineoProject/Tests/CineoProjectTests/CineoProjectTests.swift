import Foundation
import Testing
@testable import CineoProject

struct CineoProjectTests {
    private func fixture() -> CineoManifest {
        let source = MediaSource(relativePath: "Media/capture.mov", pixelWidth: 1920,
                                 pixelHeight: 1080, duration: 20)
        return CineoManifest(title: "Product demo", canvas: Canvas(width: 1080, height: 1920),
                             sources: [source], edits: [
                                SourceEdit(sourceID: source.id, sourceStart: 2, sourceEnd: 6, speed: 2),
                                SourceEdit(sourceID: source.id, sourceStart: 10, sourceEnd: 18)
                             ])
    }

    @Test func clipsMapOutputTimePreciselyAndRespectBoundary() throws {
        let project = fixture()
        #expect(try TimelineMapper.outputDuration(for: project) == 10)
        #expect(try TimelineMapper.source(at: 0, in: project)?.sourceTime == 2)
        #expect(try TimelineMapper.source(at: 1, in: project)?.sourceTime == 4)
        #expect(try TimelineMapper.source(at: 2, in: project)?.sourceTime == 10)
        #expect(try TimelineMapper.source(at: 9.9, in: project)?.sourceTime == 17.9)
        #expect(try TimelineMapper.source(at: 10, in: project) == nil)
        #expect(try TimelineMapper.source(at: -0.1, in: project) == nil)
        #expect(try TimelineMapper.source(at: .nan, in: project) == nil)
    }

    @Test func roundTripPreservesManifestAndSources() throws {
        let project = fixture()
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString + ".cineo", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = CineoProjectStore()
        try store.save(project, in: root)
        #expect(try store.load(from: root) == project)
        // Persisted edit changes cannot touch media. Import refuses overwrite.
        let sourceFile = root.deletingLastPathComponent()
            .appendingPathComponent(UUID().uuidString + ".mov")
        defer { try? FileManager.default.removeItem(at: sourceFile) }
        try Data("SOURCE".utf8).write(to: sourceFile)
        let copied = try store.importMedia(from: sourceFile, into: root, filename: "capture.mov")
        var edited = project
        edited.title = "Renamed demo"
        try store.save(edited, in: root)
        #expect(try Data(contentsOf: copied) == Data("SOURCE".utf8))
        #expect(try store.load(from: root).title == "Renamed demo")
        #expect(throws: ProjectError.invalidSource) {
            try store.importMedia(from: sourceFile, into: root, filename: "capture.mov")
        }
    }

    @Test func traversalAndInvalidDimensionsRejected() {
        for path in ["../outside.mov", "Media/../../token", "/tmp/out.mov",
                     "Media/..", "Media//bad.mov", "Media\\bad.mov", "Media/."] {
            #expect(!CineoManifest.validRelativeMediaPath(path))
        }
        #expect(CineoManifest.validRelativeMediaPath("Media/capture.mov"))
        var project = fixture()
        project.canvas.width = 0
        #expect(throws: ProjectError.invalidCanvas) { try project.validate() }
    }

    @Test func invalidTimelineAndUnknownSourcesRejected() {
        var project = fixture()
        project.edits[0].speed = 0
        #expect(throws: ProjectError.invalidEdit) { try project.validate() }
        project = fixture()
        project.edits[0].sourceID = UUID()
        #expect(throws: ProjectError.invalidEdit) { try project.validate() }
    }

    @Test func unsupportedSchemaCannotBeSilentlyRewritten() {
        var project = fixture()
        project.schemaVersion = 999
        #expect(throws: ProjectError.unsupportedVersion(999)) { try project.validate() }
    }

    @Test func duplicateSourceIDsRejected() {
        var project = fixture()
        project.sources.append(project.sources[0])
        #expect(throws: ProjectError.duplicateSource) { try project.validate() }
    }

    @Test func emptyEditsMeanZeroLengthWithoutChangingMedia() throws {
        var project = fixture()
        project.edits = []
        #expect(try TimelineMapper.outputDuration(for: project) == 0)
        #expect(try TimelineMapper.source(at: 0, in: project) == nil)
    }
}
