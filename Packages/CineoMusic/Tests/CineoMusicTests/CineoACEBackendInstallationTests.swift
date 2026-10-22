import Foundation
import XCTest
@testable import CineoMusic

final class CineoACEBackendInstallationTests: XCTestCase {
    func testServerAlwaysUsesLoopbackWithExplicitModels() {
        let root = URL(fileURLWithPath: "/tmp/ace-install")
        let command = CineoACEBackendInstallation(root: root).launchArguments
        XCTAssertEqual(command.prefix(4), ["--host", "127.0.0.1", "--port", "8080"])
        XCTAssertEqual(command.last, "/tmp/ace-install/models")
        XCTAssertFalse(command.contains("0.0.0.0"))
    }

    func testMissingModelsAreReportedRatherThanDownloaded() throws {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("ace-test-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        try FileManager.default.createDirectory(at: folder.appendingPathComponent("models"),
                                                 withIntermediateDirectories: true)
        let installation = CineoACEBackendInstallation(root: folder)
        XCTAssertEqual(installation.unavailableModels().count, 4)
        XCTAssertThrowsError(try installation.validateForLaunch())
        let bogus = installation.modelsURL.appendingPathComponent("vae-BF16.gguf")
        try Data("GGUF".utf8).write(to: bogus)
        XCTAssertTrue(installation.unavailableModels().contains("vae-BF16.gguf"),
                      "Truncated GGUF must never pass readiness preflight")
    }

    func testCandidateDirectoriesAreAbsoluteAndUnique() {
        let roots = CineoACEBackendInstallation.candidateRoots(
            home: URL(fileURLWithPath: "/Users/test"),
            workingDirectory: URL(fileURLWithPath: "/Users/test/Personal/cineo"))
        XCTAssertEqual(Set(roots.map(\.path)).count, roots.count)
        XCTAssertTrue(roots.contains {
            $0.path == "/Users/test/Personal/cineo/acestep.cpp"
        })
    }
}
