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
        let historyAction1 = session.undo()
        #expect(historyAction1)
        #expect(session.current == original)
        let historyAction2 = session.redo()
        #expect(historyAction2)
        #expect(try TimelineMapper.outputDuration(for: session.current) == 6.5)
        #expect(session.current.sources == original.sources)
    }

    @Test func invalidOperationNeverChangesStateOrRedo() throws {
        var session = try CineoEditHistory(project: fixture())
        try session.perform(.rename("Changed"))
        let historyAction3 = session.undo()
        #expect(historyAction3)
        #expect(throws: EditHistoryError.invalidIndex) {
            try session.perform(.remove(at: 99))
        }
        #expect(session.current.title == "Demo")
        #expect(session.canRedo)
        let historyAction4 = session.redo()
        #expect(historyAction4)
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
        let historyAction5 = !session.undo()
        #expect(historyAction5)
    }

    @Test func newEditAfterUndoClearsRedo() throws {
        var session = try CineoEditHistory(project: fixture())
        try session.perform(.rename("A"))
        try session.perform(.rename("B"))
        let historyAction6 = session.undo()
        #expect(historyAction6)
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
        let historyAction7 = session.undo()
        #expect(historyAction7)
        let historyAction8 = session.undo()
        #expect(historyAction8)
        let historyAction9 = !session.undo()
        #expect(historyAction9)
        #expect(session.current.title == "A")
    }

    @Test func moveSegmentPreservesPhysicalSourceTime() throws {
        var session = try CineoEditHistory(project: fixture())
        try session.perform(.move(from: 1, to: 0))
        #expect(try TimelineMapper.source(at: 0, in: session.current)?.sourceTime == 15)
        let historyAction10 = session.undo()
        #expect(historyAction10)
        #expect(try TimelineMapper.source(at: 0, in: session.current)?.sourceTime == 0)
    }

    @Test func invalidCapacityRejected() throws {
        #expect(throws: EditHistoryError.invalidCapacity) {
            try CineoEditHistory(project: fixture(), capacity: 0)
        }
    }
}
