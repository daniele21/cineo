import Foundation
import Testing
@testable import CineoEvents

struct CineoEventsTests {
    @Test func clipAnchorAndDisplayOffset() throws {
        let clock = try CineoCaptureClock(firstFrameHostSeconds: 120.0, firstFramePTSSeconds: 9.8)
        #expect(clock.relativeSeconds(hostSeconds: 120.5, recordedDuration: 25) == 0.5)
        #expect(clock.relativeSeconds(hostSeconds: 119.5, recordedDuration: 25) == nil)
        #expect(clock.relativeSeconds(hostSeconds: 145, recordedDuration: 25) == nil)
        let secondaryDisplay = CineoCaptureRect(x: 1512, y: 0, width: 1512, height: 982)
        let point = try #require(secondaryDisplay.normalize(globalX: 2268, globalY: 491))
        #expect(point.x == 0.5)
        #expect(point.y == 0.5)
        #expect(secondaryDisplay.normalize(globalX: 500, globalY: 491) == nil)
    }

    @Test func standaloneRecordingSidecarRoundTrip() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let video = dir.appendingPathComponent("demo.mp4")
        let original = try CineoPointerSidecar(events: [
            .init(sourceSeconds: 1.2, x: 0.25, y: 0.9, kind: .leftClick)
        ])
        let storage = CineoPointerRecordingStore()
        try storage.save(original, for: video)
        #expect(try storage.load(for: video) == original)
        #expect(storage.sidecarURL(for: video).lastPathComponent == "demo.pointer-events.json")
    }

    @Test func strictMouseSchemaAndOrdering() throws {
        let ok = CineoPointerEvent(sourceSeconds: 2, x: 0.2, y: 0.7, kind: .leftClick)
        let sidecar = try CineoPointerSidecar(events: [ok])
        try sidecar.validate()
        #expect(try JSONEncoder().encode(sidecar).count > 0)
        #expect(throws: CineoEventsError.invalidEvent) {
            try CineoPointerSidecar(events: [
                .init(sourceSeconds: 3, x: 0.1, y: 0.2, kind: .moved),
                .init(sourceSeconds: 2, x: 0.1, y: 0.2, kind: .leftClick)
            ])
        }
        #expect(throws: CineoEventsError.invalidEvent) {
            try CineoPointerSidecar(events: [
                .init(sourceSeconds: 1, x: .nan, y: 0.2, kind: .leftClick)
            ])
        }
    }

    @Test func atomicSidecarRoundTripAndNoKeystrokes() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString + ".cineo")
        defer { try? FileManager.default.removeItem(at: dir) }
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let sidecar = try CineoPointerSidecar(events: [
            .init(sourceSeconds: 1.25, x: 0.3, y: 0.8, kind: .rightClick)
        ])
        try CineoPointerSidecarStore().save(sidecar, projectURL: dir)
        #expect(try CineoPointerSidecarStore().load(projectURL: dir) == sidecar)
        let raw = try String(contentsOf: dir.appendingPathComponent("Effects/pointer-events.json"), encoding: .utf8)
        #expect(!raw.contains("keystroke"))
        #expect(!raw.contains("text"))
        #expect(!raw.contains("clipboard"))
    }
}
