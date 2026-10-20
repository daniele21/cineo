import Foundation
import Testing
@testable import CineoProject

struct CineoEditHistoryTests {
    private func fixture() -> CineoManifest {
        let media = MediaSource(relativePath: "Media/take.mov", pixelWidth: 1920,
                                pixelHeight: 1080, duration: 30)
        return CineoManifest(
            title: "Demo", canvas: Canvas(width: 1920, height: 1080),
            sources: [media], edits: [
                SourceEdit(sourceID: media.id, sourceStart: 0, sourceEnd: 5),
                SourceEdit(sourceID: media.id, sourceStart: 15, sourceEnd: 20)
            ]
        )
    }

    @Test func editUndoRedoRetainsOriginalMediaAndTimeMap() throws {
        let original = fixture()
        var session = try CineoEditHistory(project: original)
        try session.perform(.replace(
            SourceEdit(sourceID: original.sources[0].id, sourceStart: 2,
                       sourceEnd: 5, speed: 2), at: 0
        ))
        #expect(try TimelineMapper.outputDuration(for: session.current) == 6.5)
        #expect(session.canUndo)
        #expect(session.undo())
        #expect(session.current == original)
        #expect(session.redo())
        #expect(try TimelineMapper.outputDuration(for: session.current) == 6.5)
        #expect(session.current.sources == original.sources)
    }

    @Test func invalidOperationNeverChangesStateOrRedo() throws {
        var session = try CineoEditHistory(project: fixture())
        try session.perform(.rename("Changed"))
        #expect(session.undo())
        #expect(throws: EditHistoryError.invalidIndex) {
            try session.perform(.remove(at: 99))
        }
        #expect(session.current.title == "Demo")
        #expect(session.canRedo)
        #expect(session.redo())
        #expect(session.current.title == "Changed")
    }

    @Test func invalidManifestNeverChangesState() throws {
        var session = try CineoEditHistory(project: fixture())
        #expect(throws: ProjectError.invalidCanvas) {
            try session.perform(.setCanvas(Canvas(width: 0, height: 1920)))
        }
        #expect(!session.canUndo)
        #expect(session.current.canvas.width == 1920)
    }

    @Test func noOpDoesNotPolluteUndoHistory() throws {
        var session = try CineoEditHistory(project: fixture())
        try session.perform(.rename("Demo"))
        #expect(session.undoDepth == 0)
        #expect(!session.undo())
    }

    @Test func newEditAfterUndoClearsRedo() throws {
        var session = try CineoEditHistory(project: fixture())
        try session.perform(.rename("A"))
        try session.perform(.rename("B"))
        #expect(session.undo())
        #expect(session.canRedo)
        try session.perform(.rename("C"))
        #expect(!session.canRedo)
        #expect(session.current.title == "C")
    }

    @Test func memoryBoundAndEmptyUndoHandled() throws {
        var session = try CineoEditHistory(project: fixture(), capacity: 2)
        try session.perform(.rename("A"))
        try session.perform(.rename("B"))
        try session.perform(.rename("C"))
        #expect(session.undoDepth == 2)
        #expect(session.undo())
        #expect(session.undo())
        #expect(!session.undo())
        #expect(session.current.title == "A")
    }

    @Test func moveSegmentPreservesPhysicalSourceTime() throws {
        var session = try CineoEditHistory(project: fixture())
        try session.perform(.move(from: 1, to: 0))
        #expect(try TimelineMapper.source(at: 0, in: session.current)?.sourceTime == 15)
        #expect(session.undo())
        #expect(try TimelineMapper.source(at: 0, in: session.current)?.sourceTime == 0)
    }

    @Test func invalidCapacityRejected() throws {
        #expect(throws: EditHistoryError.invalidCapacity) {
            try CineoEditHistory(project: fixture(), capacity: 0)
        }
    }
}
