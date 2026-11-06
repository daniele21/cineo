import Foundation
import CryptoKit

/// Versioned on-device cache for pixel-derived UI change candidates. No video
/// frames, screenshots, text/OCR or hidden click-like events are persisted.
public struct CineoVisualChangeReport: Codable, Sendable {
    public let version: Int
    public let sourceDuration: Double
    public let provenance: String
    public let changes: [CineoVisualChangeCandidate]

    public init(sourceDuration: Double, changes: [CineoVisualChangeCandidate]) throws {
        version = 1
        self.sourceDuration = sourceDuration
        provenance = "pixel-ui-difference"
        self.changes = changes
        try validate()
    }

    public func validate() throws {
        guard version == 1, provenance == "pixel-ui-difference",
              sourceDuration.isFinite && sourceDuration > 0,
              changes.count <= 2_000,
              changes.allSatisfy {
                  $0.sourceSeconds.isFinite && $0.sourceSeconds >= 0 &&
                  $0.sourceSeconds < sourceDuration &&
                  $0.x.isFinite && (0...1).contains($0.x) &&
                  $0.y.isFinite && (0...1).contains($0.y) &&
                  $0.confidence.isFinite && (0...1).contains($0.confidence) &&
                  $0.changedFraction.isFinite &&
                  (0...1).contains($0.changedFraction)
              },
              zip(changes, changes.dropFirst()).allSatisfy {
                  $0.0.sourceSeconds < $0.1.sourceSeconds
              }
        else { throw CineoVisualAnalysisError.invalidVideo }
    }
}

public struct CineoVisualChangeStore: Sendable {
    public init() {}

    public func save(_ report: CineoVisualChangeReport, forVideo url: URL) throws {
        try report.validate()
        try JSONEncoder().encode(report).write(to: cachePath(for: url), options: .atomic)
    }

    public func load(forVideo url: URL) throws -> CineoVisualChangeReport {
        try read(cachePath(for: url))
    }

    public func save(_ report: CineoVisualChangeReport, projectURL: URL) throws {
        try report.validate()
        try JSONEncoder().encode(report).write(
            to: projectPath(projectURL), options: .atomic)
    }

    public func load(projectURL: URL) throws -> CineoVisualChangeReport {
        try read(projectPath(projectURL))
    }

    private func read(_ url: URL) throws -> CineoVisualChangeReport {
        let data = try Data(contentsOf: url)
        guard data.count <= 1_000_000 else { throw CineoVisualAnalysisError.invalidVideo }
        let report = try JSONDecoder().decode(CineoVisualChangeReport.self, from: data)
        try report.validate()
        return report
    }

    private func cachePath(for video: URL) throws -> URL {
        guard video.isFileURL, FileManager.default.isReadableFile(atPath: video.path),
              !((try? video.resourceValues(forKeys: [.isSymbolicLinkKey]))?.isSymbolicLink ?? false)
        else { throw CineoVisualAnalysisError.invalidVideo }
        let attrs = try FileManager.default.attributesOfItem(atPath: video.path)
        guard let size = attrs[.size] as? NSNumber,
              let modified = attrs[.modificationDate] as? Date,
              let support = FileManager.default.urls(
                for: .applicationSupportDirectory, in: .userDomainMask).first
        else { throw CineoVisualAnalysisError.invalidVideo }
        let identity = "\(video.standardizedFileURL.path)|\(size.int64Value)|\(modified.timeIntervalSince1970)"
        let digest = SHA256.hash(data: Data(identity.utf8))
            .map { String(format: "%02x", $0) }.joined()
        let dir = support.appendingPathComponent("Cineo/VisualAnalysis", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent(digest + ".json")
    }

    private func projectPath(_ project: URL) throws -> URL {
        guard project.isFileURL, project.pathExtension.lowercased() == "cineo",
              FileManager.default.fileExists(atPath: project.path),
              !((try? project.resourceValues(forKeys: [.isSymbolicLinkKey]))?.isSymbolicLink ?? false)
        else { throw CineoVisualAnalysisError.invalidVideo }
        let dir = project.appendingPathComponent("Effects", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        guard !((try? dir.resourceValues(forKeys: [.isSymbolicLinkKey]))?.isSymbolicLink ?? false),
              dir.resolvingSymlinksInPath().standardizedFileURL ==
                 project.resolvingSymlinksInPath().appendingPathComponent("Effects").standardizedFileURL
        else { throw CineoVisualAnalysisError.invalidVideo }
        return dir.appendingPathComponent("visual-change-analysis.json")
    }
}
