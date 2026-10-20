import Foundation
import Testing
@testable import CineoProject

struct CineoRecordingImportTests {
    @Test func originalRetainedAndReopenable() throws {
        let temp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: temp) }
        try FileManager.default.createDirectory(at: temp, withIntermediateDirectories: true)
        let recording = temp.appendingPathComponent("capture.mp4")
        let projectURL = temp.appendingPathComponent("my-demo.cineo")
        let original = Data("RAW_VIDEO_FIXTURE".utf8)
        try original.write(to: recording)
        let manifest = try CineoRecordingImporter().createProject(
            from: recording, at: projectURL, width: 1512, height: 982,
            durationSeconds: 25, title: "Test capture"
        )
        #expect(manifest.sources.count == 1)
        #expect(manifest.edits.count == 1)
        #expect(try CineoProjectStore().load(from: projectURL) == manifest)
        let copied = projectURL.appendingPathComponent(manifest.sources[0].relativePath)
        #expect(try Data(contentsOf: copied) == original)
        #expect(try Data(contentsOf: recording) == original)
        #expect(throws: ProjectError.invalidPackageLocation) {
            try CineoRecordingImporter().createProject(
                from: recording, at: projectURL, width: 1512, height: 982,
                durationSeconds: 25, title: "No overwrite"
            )
        }
        #expect(try Data(contentsOf: copied) == original)
    }

    @Test func invalidMetadataLeavesNoProject() throws {
        let temp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: temp) }
        try FileManager.default.createDirectory(at: temp, withIntermediateDirectories: true)
        let recording = temp.appendingPathComponent("capture.mp4")
        try Data("VIDEO".utf8).write(to: recording)
        let destination = temp.appendingPathComponent("invalid.cineo")
        #expect(throws: ProjectError.invalidSource) {
            try CineoRecordingImporter().createProject(
                from: recording, at: destination, width: 0, height: 100,
                durationSeconds: .nan, title: "Invalid"
            )
        }
        #expect(!FileManager.default.fileExists(atPath: destination.path))
    }
}
