import Foundation
import CryptoKit
import CineoDirector

/// Persist only normalized coordinates/confidence and timestamps, never frames.
/// Cache identity includes path, size and mtime to avoid reusing stale analysis
/// after most edits or replacements of an imported MP4.
public struct CineoImportedAnalysisStore: Sendable {
    public init() {}

    public func load(forVideo source: URL) throws -> CineoImportedPointerAnalysis {
        let target = try cacheURL(for: source)
        return try decode(target)
    }

    public func save(_ analysis: CineoImportedPointerAnalysis, forVideo source: URL) throws {
        try analysis.validate()
        try encode(analysis, to: cacheURL(for: source))
    }

    public func load(projectURL: URL) throws -> CineoImportedPointerAnalysis {
        return try decode(try projectFile(projectURL))
    }

    public func save(_ analysis: CineoImportedPointerAnalysis, projectURL: URL) throws {
        try analysis.validate()
        let target = try projectFile(projectURL)
        try encode(analysis, to: target)
    }

    private func projectFile(_ url: URL) throws -> URL {
        guard url.isFileURL, url.pathExtension.lowercased() == "cineo",
              FileManager.default.fileExists(atPath: url.path),
              !((try? url.resourceValues(forKeys: [.isSymbolicLinkKey]))?.isSymbolicLink ?? false)
        else { throw CineoVideoTrackingError.invalidSource }
        let directory = url.appendingPathComponent("Effects", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        guard directory.resolvingSymlinksInPath().standardizedFileURL ==
              url.resolvingSymlinksInPath().appendingPathComponent("Effects").standardizedFileURL,
              !((try? directory.resourceValues(forKeys: [.isSymbolicLinkKey]))?.isSymbolicLink ?? false)
        else { throw CineoVideoTrackingError.invalidSource }
        return directory.appendingPathComponent("imported-video-analysis.json")
    }

    private func cacheURL(for video: URL) throws -> URL {
        guard video.isFileURL, FileManager.default.isReadableFile(atPath: video.path),
              !((try? video.resourceValues(forKeys: [.isSymbolicLinkKey]))?.isSymbolicLink ?? false)
        else { throw CineoVideoTrackingError.invalidSource }
        let attributes = try FileManager.default.attributesOfItem(atPath: video.path)
        guard let size = attributes[.size] as? NSNumber,
              let modified = attributes[.modificationDate] as? Date else {
            throw CineoVideoTrackingError.invalidSource
        }
        let fingerprint = "\(video.standardizedFileURL.path)|\(size.int64Value)|\(modified.timeIntervalSince1970)"
        let digest = SHA256.hash(data: Data(fingerprint.utf8))
            .map { String(format: "%02x", $0) }.joined()
        guard let support = FileManager.default.urls(for: .applicationSupportDirectory,
                                                    in: .userDomainMask).first
        else { throw CineoVideoTrackingError.invalidSource }
        let directory = support.appendingPathComponent("Cineo/VideoAnalysis", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appendingPathComponent(digest + ".json")
    }

    private func encode(_ value: CineoImportedPointerAnalysis, to url: URL) throws {
        let data = try JSONEncoder().encode(value)
        try data.write(to: url, options: .atomic)
    }

    private func decode(_ url: URL) throws -> CineoImportedPointerAnalysis {
        let data = try Data(contentsOf: url)
        guard data.count <= 6_000_000 else { throw CineoVideoTrackingError.invalidSource }
        let report = try JSONDecoder().decode(CineoImportedPointerAnalysis.self, from: data)
        try report.validate()
        return report
    }
}
