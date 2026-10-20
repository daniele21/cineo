import Foundation
import CineoDirector
import CineoProject

/// Attention timestamp expressed in the original source media timebase.
/// The capture layer must measure any wall-clock -> PTS drift before creating
/// these events. No typed text, pixels or filenames enter this model.
public struct SourceAttentionEvent: Codable, Sendable, Equatable {
    public let sourceID: UUID
    public let sourceTime: Double
    public let x: Double
    public let y: Double
    public let kind: AttentionEvent.Kind

    public init(sourceID: UUID, sourceTime: Double, x: Double, y: Double,
                kind: AttentionEvent.Kind) {
        self.sourceID = sourceID
        self.sourceTime = sourceTime
        self.x = x
        self.y = y
        self.kind = kind
    }
}

public struct SuggestedCameraPlan: Codable, Sendable, Equatable {
    public static let supportedVersion = 1
    public let schemaVersion: Int
    public let projectID: UUID
    /// Output timeline duration (seconds) used to generate this plan.
    public let outputDuration: Double
    public let shots: [CameraShot]

    public init(projectID: UUID, outputDuration: Double, shots: [CameraShot]) {
        self.schemaVersion = Self.supportedVersion
        self.projectID = projectID
        self.outputDuration = outputDuration
        self.shots = shots
    }

    public func validate(against project: CineoManifest) throws {
        guard schemaVersion == Self.supportedVersion,
              projectID == project.projectID,
              outputDuration.isFinite, outputDuration >= 0,
              abs(outputDuration - (try TimelineMapper.outputDuration(for: project))) < 0.000001
        else { throw SuggestedCameraError.incompatibleProject }
        for shot in shots {
            guard shot.start.isFinite, shot.end.isFinite,
                  shot.start >= 0, shot.start < shot.end,
                  shot.end <= outputDuration,
                  shot.focusX.isFinite, shot.focusY.isFinite,
                  (0...1).contains(shot.focusX), (0...1).contains(shot.focusY),
                  shot.zoom.isFinite, shot.zoom > 1 else {
                throw SuggestedCameraError.invalidShot
            }
        }
        for i in shots.indices.dropFirst() {
            guard shots[i].start >= shots[i - 1].end else {
                throw SuggestedCameraError.invalidShot
            }
        }
    }
}

public enum SuggestedCameraError: Error, Equatable {
    case incompatibleProject
    case invalidShot
}

/// Converts original media PTS into the *edited* output timeline before
/// passing events to the deterministic camera planner.
/// Repeated source clips intentionally replay their matching events.
public struct CineoEditPlanner: Sendable {
    public let camera: CameraPlanner

    public init(camera: CameraPlanner = CameraPlanner()) {
        self.camera = camera
    }

    public func suggest(for project: CineoManifest,
                        events: [SourceAttentionEvent]) throws -> SuggestedCameraPlan {
        let duration = try TimelineMapper.outputDuration(for: project)
        var timelineEvents: [AttentionEvent] = []
        var outputOffset = 0.0
        for clip in project.edits {
            for event in events where event.sourceID == clip.sourceID {
                guard event.sourceTime.isFinite,
                      event.sourceTime >= clip.sourceStart,
                      event.sourceTime < clip.sourceEnd
                else { continue }
                let time = outputOffset + (event.sourceTime - clip.sourceStart) / clip.speed
                timelineEvents.append(AttentionEvent(
                    time: time, x: event.x, y: event.y, kind: event.kind
                ))
            }
            outputOffset += (clip.sourceEnd - clip.sourceStart) / clip.speed
        }
        let shots = camera.suggest(events: timelineEvents, duration: duration)
        let plan = SuggestedCameraPlan(projectID: project.projectID,
                                       outputDuration: duration, shots: shots)
        try plan.validate(against: project)
        return plan
    }
}

/// Stores suggestions as a sidecar instead of mutating source media or manually
/// edited camera tracks. Regeneration can safely replace suggestions alone.
public struct SuggestedCameraStore: Sendable {
    public init() {}

    public func save(_ plan: SuggestedCameraPlan, project: CineoManifest, in directory: URL) throws {
        guard directory.pathExtension == "cineo" else { throw ProjectError.invalidPackageLocation }
        try plan.validate(against: project)
        let effects = directory.appendingPathComponent("Effects", isDirectory: true)
        try FileManager.default.createDirectory(at: effects, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        try encoder.encode(plan).write(
            to: effects.appendingPathComponent("camera-suggestions.json"), options: .atomic
        )
    }

    public func load(project: CineoManifest, from directory: URL) throws -> SuggestedCameraPlan {
        guard directory.pathExtension == "cineo" else { throw ProjectError.invalidPackageLocation }
        let path = directory.appendingPathComponent("Effects/camera-suggestions.json")
        let plan = try JSONDecoder().decode(SuggestedCameraPlan.self, from: Data(contentsOf: path))
        try plan.validate(against: project)
        return plan
    }
}
