import Foundation
import Testing
import CineoDirector
import CineoProject
@testable import CineoEditPlanner

struct CineoEditPlannerTests {
    private func sample() -> CineoManifest {
        let src = MediaSource(relativePath: "Media/source.mov", pixelWidth: 1920,
                              pixelHeight: 1080, duration: 20)
        return CineoManifest(title: "Sample", canvas: Canvas(width: 1920, height: 1080),
                             sources: [src], edits: [
                                SourceEdit(sourceID: src.id, sourceStart: 2, sourceEnd: 6, speed: 2),
                                SourceEdit(sourceID: src.id, sourceStart: 10, sourceEnd: 14)
                             ])
    }

    @Test func sourceClockMapsThroughCutAndSpeedToEditedTimeline() throws {
        let p = sample(), id = p.sources[0].id
        let events = [
            SourceAttentionEvent(sourceID: id, sourceTime: 3, x: 0.2, y: 0.5, kind: .click),
            SourceAttentionEvent(sourceID: id, sourceTime: 11, x: 0.8, y: 0.5, kind: .result)
        ]
        let plan = try CineoEditPlanner().suggest(for: p, events: events)
        #expect(plan.outputDuration == 6)
        #expect(plan.shots.count == 2)
        #expect(plan.shots[0].reason == .clickCluster)
        #expect(plan.shots[0].start < 0.5)
        #expect(plan.shots[1].reason == .result)
        #expect(plan.shots[1].start >= 2)
        try plan.validate(against: p)
    }

    @Test func trimmedAndUnknownSourceEventsAreIgnored() throws {
        let p = sample(), id = p.sources[0].id
        let events = [
            SourceAttentionEvent(sourceID: id, sourceTime: 0.5, x: 0.5, y: 0.5, kind: .click),
            SourceAttentionEvent(sourceID: UUID(), sourceTime: 3, x: 0.5, y: 0.5, kind: .click),
            SourceAttentionEvent(sourceID: id, sourceTime: 6.0, x: 0.5, y: 0.5, kind: .click),
            SourceAttentionEvent(sourceID: id, sourceTime: .nan, x: 0.5, y: 0.5, kind: .result)
        ]
        #expect(try CineoEditPlanner().suggest(for: p, events: events).shots.isEmpty)
    }

    @Test func repeatedSourceClipMapsEventTwice() throws {
        let p = sample()
        let id = p.sources[0].id
        var repeated = p
        repeated.edits = [
            SourceEdit(sourceID: id, sourceStart: 2, sourceEnd: 4),
            SourceEdit(sourceID: id, sourceStart: 2, sourceEnd: 4)
        ]
        let events = [SourceAttentionEvent(sourceID: id, sourceTime: 3, x: 0.5, y: 0.5, kind: .result)]
        let plan = try CineoEditPlanner().suggest(for: repeated, events: events)
        #expect(plan.shots.count == 2)
        #expect(plan.shots[0].start < 1)
        #expect(plan.shots[1].start >= 2)
    }

    @Test func suggestionsRoundTripWithoutMutatingManifest() throws {
        let p = sample()
        let base = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString + ".cineo", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: base) }
        try CineoProjectStore().save(p, in: base)
        let plan = try CineoEditPlanner().suggest(
            for: p, events: [SourceAttentionEvent(sourceID: p.sources[0].id,
                           sourceTime: 11, x: 0.5, y: 0.5, kind: .result)]
        )
        let store = SuggestedCameraStore()
        try store.save(plan, project: p, in: base)
        #expect(try store.load(project: p, from: base) == plan)
        #expect(try CineoProjectStore().load(from: base) == p)
    }

    @Test func staleCameraPlanIsRejectedAfterEditChanges() throws {
        let project = sample()
        let plan = try CineoEditPlanner().suggest(for: project, events: [])
        var edited = project
        edited.edits[0].speed = 1
        #expect(throws: SuggestedCameraError.incompatibleProject) {
            try plan.validate(against: edited)
        }
    }
}
