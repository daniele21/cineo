import Foundation

/// Opt-in capture metadata sits next to its original MP4; importing the video
/// into a .cineo project copies this data into Effects/pointer-events.json.
public struct CineoPointerRecordingStore: Sendable {
    public init() {}
    public func sidecarURL(for video: URL) -> URL {
        video.deletingPathExtension().appendingPathExtension("pointer-events.json")
    }

    public func save(_ sidecar: CineoPointerSidecar, for video: URL) throws {
        guard video.isFileURL, video.pathExtension.lowercased() == "mp4" else {
            throw CineoEventsError.invalidPackage
        }
        try sidecar.validate()
        let path = sidecarURL(for: video)
        let data = try JSONEncoder().encode(sidecar)
        try data.write(to: path, options: .atomic)
    }

    public func load(for video: URL) throws -> CineoPointerSidecar {
        guard video.isFileURL, video.pathExtension.lowercased() == "mp4" else {
            throw CineoEventsError.invalidPackage
        }
        let url = sidecarURL(for: video)
        let data = try Data(contentsOf: url)
        let sidecar = try JSONDecoder().decode(CineoPointerSidecar.self, from: data)
        try sidecar.validate()
        return sidecar
    }
}
