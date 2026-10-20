import Foundation

/// Bridges an already VERIFIED capture into a versioned, non-destructive project.
/// The capture layer supplies probed dimensions/duration; this API never assumes
/// that a stream-start callback guarantees a valid movie.
public struct CineoRecordingImporter: Sendable {
    public init() {}

    /// Existing projects are never replaced by a new recording import.
    /// The original recording stays in place; an independent media copy is made.
    public func createProject(
        from recording: URL,
        at projectURL: URL,
        width: Int,
        height: Int,
        durationSeconds: Double,
        title: String
    ) throws -> CineoManifest {
        guard projectURL.pathExtension == "cineo" else {
            throw ProjectError.invalidPackageLocation
        }
        guard width > 0, height > 0,
              durationSeconds.isFinite, durationSeconds > 0,
              recording.isFileURL,
              FileManager.default.isReadableFile(atPath: recording.path),
              !((try? recording.resourceValues(forKeys: [.isSymbolicLinkKey]))?.isSymbolicLink ?? false)
        else { throw ProjectError.invalidSource }
        // Never silently overwrite an existing project or leave partial media
        // inside its package if the import fails.
        guard !FileManager.default.fileExists(atPath: projectURL.path) else {
            throw ProjectError.invalidPackageLocation
        }
        let sourceID = UUID()
        let filename = "capture-\(sourceID.uuidString.lowercased()).mp4"
        let source = MediaSource(id: sourceID,
                                 relativePath: "Media/\(filename)",
                                 pixelWidth: width,
                                 pixelHeight: height,
                                 duration: durationSeconds)
        let project = CineoManifest(
            title: title, canvas: Canvas(width: width, height: height),
            sources: [source],
            edits: [SourceEdit(sourceID: sourceID, sourceStart: 0, sourceEnd: durationSeconds)]
        )
        try project.validate()
        let store = CineoProjectStore()
        do {
            _ = try store.importMedia(from: recording, into: projectURL, filename: filename)
            try store.save(project, in: projectURL)
            return project
        } catch {
            // Ownership is exclusive: destination did not exist at entry.
            // Never delete an existing project or the caller's original file.
            try? FileManager.default.removeItem(at: projectURL)
            throw error
        }
    }
}
