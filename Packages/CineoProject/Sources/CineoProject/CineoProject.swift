import Foundation

/// Platform-independent, versioned Cineo edit description.
/// Recording media is always external to this JSON; no file bytes or
/// keystroke content are serialized in a project manifest.
public struct CineoManifest: Codable, Equatable, Sendable {
    public static let supportedVersion = 1
    public var schemaVersion: Int
    public var projectID: UUID
    public var title: String
    public var canvas: Canvas
    public var sources: [MediaSource]
    public var edits: [SourceEdit]

    public init(projectID: UUID = UUID(), title: String, canvas: Canvas,
                sources: [MediaSource], edits: [SourceEdit]) {
        self.schemaVersion = Self.supportedVersion
        self.projectID = projectID
        self.title = title
        self.canvas = canvas
        self.sources = sources
        self.edits = edits
    }

    public func validate() throws {
        guard schemaVersion == Self.supportedVersion else { throw ProjectError.unsupportedVersion(schemaVersion) }
        guard !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw ProjectError.invalidManifest }
        guard canvas.width > 0, canvas.height > 0 else { throw ProjectError.invalidCanvas }
        let ids = sources.map(\.id)
        guard Set(ids).count == ids.count else { throw ProjectError.duplicateSource }
        for source in sources {
            guard source.pixelWidth > 0, source.pixelHeight > 0,
                  source.duration.isFinite, source.duration > 0,
                  Self.validRelativeMediaPath(source.relativePath)
            else { throw ProjectError.invalidSource }
        }
        for edit in edits {
            guard sources.contains(where: {
                $0.id == edit.sourceID && edit.sourceStart >= 0 &&
                edit.sourceEnd <= $0.duration
            }), edit.sourceStart.isFinite, edit.sourceEnd.isFinite,
                  edit.sourceEnd > edit.sourceStart,
                  edit.speed.isFinite, edit.speed > 0
            else { throw ProjectError.invalidEdit }
        }
    }

    /// Sources live strictly inside the package Media directory; no traversal.
    public static func validRelativeMediaPath(_ path: String) -> Bool {
        guard !path.isEmpty, !path.hasPrefix("/"), !path.contains("\\"),
              !path.contains("\0"), !path.hasPrefix("~") else { return false }
        let parts = path.split(separator: "/", omittingEmptySubsequences: false)
        return parts.count >= 2 && parts[0] == "Media" &&
            parts.allSatisfy { !$0.isEmpty && $0 != "." && $0 != ".." }
    }
}

public struct Canvas: Codable, Equatable, Sendable {
    public var width: Int
    public var height: Int
    public init(width: Int, height: Int) { self.width = width; self.height = height }
}

public struct MediaSource: Codable, Equatable, Sendable {
    public var id: UUID
    public var relativePath: String
    public var pixelWidth: Int
    public var pixelHeight: Int
    public var duration: Double
    public init(id: UUID = UUID(), relativePath: String, pixelWidth: Int,
                pixelHeight: Int, duration: Double) {
        self.id = id
        self.relativePath = relativePath
        self.pixelWidth = pixelWidth
        self.pixelHeight = pixelHeight
        self.duration = duration
    }
}

public struct SourceEdit: Codable, Equatable, Sendable {
    public var sourceID: UUID
    public var sourceStart: Double
    public var sourceEnd: Double
    /// 2x is twice as fast, 0.5x is half speed.
    public var speed: Double
    public init(sourceID: UUID, sourceStart: Double, sourceEnd: Double, speed: Double = 1) {
        self.sourceID = sourceID
        self.sourceStart = sourceStart
        self.sourceEnd = sourceEnd
        self.speed = speed
    }
}

public enum ProjectError: Error, Equatable, Sendable {
    case unsupportedVersion(Int)
    case invalidManifest
    case invalidCanvas
    case invalidSource
    case duplicateSource
    case invalidEdit
    case invalidPackageLocation
    case missingMedia
}

public struct SourceMoment: Equatable, Sendable {
    public let sourceID: UUID
    public let sourceTime: Double
}

/// One canonical output-time-to-source-time mapper used by editor and renderer.
/// Returns nil at or beyond the end, never invents interpolated source frames.
public enum TimelineMapper {
    public static func outputDuration(for project: CineoManifest) throws -> Double {
        try project.validate()
        let duration = project.edits.reduce(0.0) {
            $0 + ($1.sourceEnd - $1.sourceStart) / $1.speed
        }
        guard duration.isFinite else { throw ProjectError.invalidEdit }
        return duration
    }

    public static func source(at outputSeconds: Double, in project: CineoManifest) throws -> SourceMoment? {
        try project.validate()
        guard outputSeconds.isFinite, outputSeconds >= 0 else { return nil }
        var start = 0.0
        for clip in project.edits {
            let length = (clip.sourceEnd - clip.sourceStart) / clip.speed
            let end = start + length
            guard end.isFinite else { throw ProjectError.invalidEdit }
            if outputSeconds < end {
                let mapped = clip.sourceStart + (outputSeconds - start) * clip.speed
                return SourceMoment(sourceID: clip.sourceID, sourceTime: min(mapped, clip.sourceEnd))
            }
            start = end
        }
        return nil
    }
}

/// Local, non-destructive package persistence. Caller chooses storage location.
/// Source files are never modified by manifest updates.
public struct CineoProjectStore: Sendable {
    public init() {}

    public func save(_ project: CineoManifest, in directory: URL) throws {
        try project.validate()
        guard directory.pathExtension == "cineo" else { throw ProjectError.invalidPackageLocation }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let media = try safeMediaDirectory(in: directory, create: true)
        for source in project.sources {
            _ = try safeSourceURL(source.relativePath, in: directory, media: media)
        }
        let data = try JSONEncoder().encode(project)
        // .atomic writes a temporary file and renames on success.
        try data.write(to: directory.appendingPathComponent("manifest.json"), options: .atomic)
    }

    public func load(from directory: URL) throws -> CineoManifest {
        guard directory.pathExtension == "cineo" else { throw ProjectError.invalidPackageLocation }
        let data = try Data(contentsOf: directory.appendingPathComponent("manifest.json"))
        let project = try JSONDecoder().decode(CineoManifest.self, from: data)
        try project.validate()
        let media = try safeMediaDirectory(in: directory, create: false)
        for source in project.sources {
            _ = try safeSourceURL(source.relativePath, in: directory, media: media)
        }
        return project
    }

    /// Copy immutable capture data into project-owned media storage.
    /// Never overwrite an existing source, including on repeated imports.
    @discardableResult
    public func importMedia(from original: URL, into directory: URL, filename: String) throws -> URL {
        guard directory.pathExtension == "cineo",
              !filename.isEmpty, !filename.contains("/"), !filename.contains("\\"),
              filename != ".", filename != "..", !filename.hasPrefix(".")
        else { throw ProjectError.invalidSource }
        let media = try safeMediaDirectory(in: directory, create: true)
        let destination = media.appendingPathComponent(filename)
        guard !FileManager.default.fileExists(atPath: destination.path),
              !((try? destination.resourceValues(forKeys: [.isSymbolicLinkKey]))?.isSymbolicLink ?? false),
              !((try? original.resourceValues(forKeys: [.isSymbolicLinkKey]))?.isSymbolicLink ?? false)
        else { throw ProjectError.invalidSource }
        try FileManager.default.copyItem(at: original, to: destination)
        return destination
    }

    /// Protect against externally created symlinked Media folders. Merely
    /// checking a manifest for '..' is not sufficient to prevent traversal.
    private func safeMediaDirectory(in root: URL, create: Bool) throws -> URL {
        guard root.pathExtension == "cineo" else { throw ProjectError.invalidPackageLocation }
        let media = root.appendingPathComponent("Media", isDirectory: true)
        if create {
            try FileManager.default.createDirectory(at: media, withIntermediateDirectories: true)
        }
        let canonicalRoot = root.resolvingSymlinksInPath().standardizedFileURL
        let expected = canonicalRoot.appendingPathComponent("Media", isDirectory: true)
        guard media.resolvingSymlinksInPath().standardizedFileURL == expected,
              !((try? media.resourceValues(forKeys: [.isSymbolicLinkKey]))?.isSymbolicLink ?? false)
        else { throw ProjectError.invalidSource }
        return media
    }

    /// Symlinks inside Media must also stay within its canonical root.
    /// A missing source is kept as a valid *reference* so the editor can
    /// report a relinkable missing-media state instead of discarding edits.
    private func safeSourceURL(_ path: String, in root: URL, media: URL) throws -> URL {
        guard CineoManifest.validRelativeMediaPath(path) else { throw ProjectError.invalidSource }
        let url = root.appendingPathComponent(path)
        let resolved = url.resolvingSymlinksInPath().standardizedFileURL.path
        let rootPath = media.resolvingSymlinksInPath().standardizedFileURL.path
        guard resolved.hasPrefix(rootPath + "/") else { throw ProjectError.invalidSource }
        return url
    }
}
