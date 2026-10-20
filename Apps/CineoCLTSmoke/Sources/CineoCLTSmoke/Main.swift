import Foundation
import CineoDirector
import CineoProject
import CineoEditPlanner

/// CLT-native smoke checks without XCTest/Swift Testing macro plugins.
/// Full regression suite still runs in Linux Swift 6.2 CI.
@main
struct CineoCLTSmoke {
    enum SmokeFailure: Error {
        case camera
        case timeline
        case editPlan
        case projectPersistence
        case undo
    }

    static func main() throws {
        let cameraEvents = [
            AttentionEvent(time: 1, x: 0.5, y: 0.5, kind: .click),
            AttentionEvent(time: 1.1, x: 0.52, y: 0.51, kind: .click)
        ]
        let camera = CameraPlanner().suggest(events: cameraEvents, duration: 10)
        guard camera.count == 1, camera[0].start >= 0, camera[0].end <= 10 else {
            throw SmokeFailure.camera
        }

        let source = MediaSource(relativePath: "Media/test.mov",
                                 pixelWidth: 1920, pixelHeight: 1080, duration: 30)
        let project = CineoManifest(
            title: "CLT test", canvas: Canvas(width: 1920, height: 1080),
            sources: [source], edits: [
                SourceEdit(sourceID: source.id, sourceStart: 2, sourceEnd: 6, speed: 2)
            ]
        )
        try project.validate()
        guard try TimelineMapper.outputDuration(for: project) == 2,
              let moment = try TimelineMapper.source(at: 0.5, in: project),
              moment.sourceTime == 3
        else { throw SmokeFailure.timeline }

        let anchor = SourceAttentionEvent(sourceID: source.id, sourceTime: 3,
                                          x: 0.5, y: 0.5, kind: .result)
        let plan = try CineoEditPlanner().suggest(for: project, events: [anchor])
        guard !plan.shots.isEmpty, plan.outputDuration == 2,
              plan.shots.allSatisfy({ $0.start >= 0 && $0.end <= 2 }) else {
            throw SmokeFailure.editPlan
        }

        var history = try CineoEditHistory(project: project)
        try history.perform(.rename("Changed"))
        guard history.current.title == "Changed", history.undo(),
              history.current.title == "CLT test", history.redo(),
              history.current.title == "Changed" else {
            throw SmokeFailure.undo
        }

        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString + ".cineo", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = CineoProjectStore()
        try store.save(project, in: folder)
        guard try store.load(from: folder) == project else {
            throw SmokeFailure.projectPersistence
        }
        print("PASS Cineo CLT smoke: camera, retimed timeline, editable camera plan, undo/redo and project round-trip.")
        print("Scope: algorithms only, no ScreenCaptureKit permissions, real video or pixel rendering.")
    }
}
