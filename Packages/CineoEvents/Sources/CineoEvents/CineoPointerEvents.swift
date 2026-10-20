import Foundation

/// Strict mouse-only telemetry. No keypress/text/window-title fields exist.
public struct CineoPointerEvent: Codable, Equatable, Sendable {
    public enum Kind: String, Codable, Sendable {
        case moved, leftClick, rightClick, scroll
    }
    public let sourceSeconds: Double
    public let x: Double
    public let y: Double
    public let kind: Kind
    public init(sourceSeconds: Double, x: Double, y: Double, kind: Kind) {
        self.sourceSeconds = sourceSeconds
        self.x = x
        self.y = y
        self.kind = kind
    }
    public var isValid: Bool {
        sourceSeconds.isFinite && sourceSeconds >= 0 &&
        x.isFinite && y.isFinite && (0...1).contains(x) && (0...1).contains(y)
    }
}

/// Each raw event is stamped with a single monotonic host-clock timestamp.
/// The actual first VIDEO frame is the anchor, not pressing Record.
public struct CineoCaptureClock: Sendable {
    public let firstFrameHostSeconds: Double
    public let firstFramePTSSeconds: Double

    public init(firstFrameHostSeconds: Double, firstFramePTSSeconds: Double) throws {
        guard firstFrameHostSeconds.isFinite, firstFramePTSSeconds.isFinite
        else { throw CineoEventsError.invalidClock }
        self.firstFrameHostSeconds = firstFrameHostSeconds
        self.firstFramePTSSeconds = firstFramePTSSeconds
    }

    /// Reject future/out-of-range input (e.g. before capture started or after
    /// the last encoded frame). Output timestamps are source-relative.
    public func relativeSeconds(hostSeconds: Double, recordedDuration: Double) -> Double? {
        guard hostSeconds.isFinite, recordedDuration.isFinite, recordedDuration > 0 else { return nil }
        let seconds = hostSeconds - firstFrameHostSeconds
        guard seconds >= 0, seconds < recordedDuration else { return nil }
        return seconds
    }
}

/// Rect is in global display *points*, origin top-left, representing the actual
/// captured content after resolving ScreenCaptureKit frame metadata offsets.
public struct CineoCaptureRect: Codable, Sendable {
    public let x: Double
    public let y: Double
    public let width: Double
    public let height: Double
    public init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x; self.y = y; self.width = width; self.height = height
    }

    public func normalize(globalX: Double, globalY: Double) -> (x: Double, y: Double)? {
        guard [x, y, width, height, globalX, globalY].allSatisfy(\.isFinite),
              width > 0, height > 0 else { return nil }
        let nx = (globalX - x) / width, ny = (globalY - y) / height
        guard (0...1).contains(nx), (0...1).contains(ny) else { return nil }
        return (nx, ny)
    }
}

public enum CineoEventsError: Error, Equatable, Sendable {
    case invalidClock
    case invalidEvent
    case unsupportedSchema
    case invalidPackage
}

public struct CineoPointerSidecar: Codable, Sendable, Equatable {
    public static let version = 1
    public let schemaVersion: Int
    public let events: [CineoPointerEvent]

    public init(events: [CineoPointerEvent]) throws {
        guard events.count <= 10_000_000,
              events.allSatisfy(\.isValid),
              zip(events, events.dropFirst()).allSatisfy({ pair in pair.0.sourceSeconds <= pair.1.sourceSeconds })
        else { throw CineoEventsError.invalidEvent }
        self.schemaVersion = Self.version
        self.events = events
    }

    public func validate() throws {
        guard schemaVersion == Self.version else { throw CineoEventsError.unsupportedSchema }
        _ = try CineoPointerSidecar(events: events)
    }
}

public struct CineoPointerSidecarStore: Sendable {
    public init() {}

    public func save(_ value: CineoPointerSidecar, projectURL: URL) throws {
        guard projectURL.pathExtension == "cineo",
              FileManager.default.fileExists(atPath: projectURL.path),
              !((try? projectURL.resourceValues(forKeys: [.isSymbolicLinkKey]))?.isSymbolicLink ?? false)
        else { throw CineoEventsError.invalidPackage }
        try value.validate()
        let directory = projectURL.appendingPathComponent("Effects", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        guard directory.resolvingSymlinksInPath().standardizedFileURL ==
              projectURL.resolvingSymlinksInPath().appendingPathComponent("Effects").standardizedFileURL
        else { throw CineoEventsError.invalidPackage }
        let data = try JSONEncoder().encode(value)
        try data.write(to: directory.appendingPathComponent("pointer-events.json"), options: .atomic)
    }

    public func load(projectURL: URL) throws -> CineoPointerSidecar {
        guard projectURL.pathExtension == "cineo" else { throw CineoEventsError.invalidPackage }
        let url = projectURL.appendingPathComponent("Effects/pointer-events.json")
        guard url.resolvingSymlinksInPath().path.hasPrefix(projectURL.resolvingSymlinksInPath().path + "/")
        else { throw CineoEventsError.invalidPackage }
        let sidecar = try JSONDecoder().decode(CineoPointerSidecar.self, from: Data(contentsOf: url))
        try sidecar.validate()
        return sidecar
    }
}
