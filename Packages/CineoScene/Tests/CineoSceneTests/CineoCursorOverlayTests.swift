import Foundation
import CineoEvents
import Testing
@testable import CineoScene

struct CineoCursorOverlayTests {
    @Test func legacyBakedCursorNeverGetsRedrawn() throws {
        let old = try CineoPointerSidecar(events: [
            .init(sourceSeconds: 0.1, x: 0.3, y: 0.4, kind: .moved)
        ])
        #expect(throws: CineoEventsError.unsupportedSchema) {
            try CineoCursorOverlay(sidecar: old)
        }
    }

    @Test func independentCursorUsesSourceTimeNotOutputTime() throws {
        let sidecar = try CineoPointerSidecar(events: [
            .init(sourceSeconds: 0, x: 0.1, y: 0.1, kind: .moved),
            .init(sourceSeconds: 0.2, x: 0.9, y: 0.8, kind: .moved),
            .init(sourceSeconds: 0.2, x: 0.92, y: 0.77, kind: .leftClick)
        ], cursorMode: .independentOverlay)
        let track = try CineoCursorOverlay(sidecar: sidecar)
        #expect(track.sampleCount == 3)
        #expect(try #require(track.position(atSourceTime: 0.2)).x == 0.92)
        #expect(track.position(atSourceTime: 0.3) == nil)
        #expect(track.position(atSourceTime: -1) == nil)
    }

    @Test func sidecarV2AndOldV1RoundTrip() throws {
        let source = [CineoPointerEvent(sourceSeconds: 0.1, x: 0.3, y: 0.7, kind: .moved)]
        let v1 = try CineoPointerSidecar(events: source)
        let v2 = try CineoPointerSidecar(events: source, cursorMode: .independentOverlay)
        #expect(v1.schemaVersion == 1)
        #expect(v2.schemaVersion == 2)
        #expect(try JSONDecoder().decode(CineoPointerSidecar.self, from: JSONEncoder().encode(v2)) == v2)
        var legacy = try JSONSerialization.jsonObject(with: JSONEncoder().encode(v1)) as! [String: Any]
        legacy.removeValue(forKey: "cursorMode")
        let data = try JSONSerialization.data(withJSONObject: legacy)
        let decoded = try JSONDecoder().decode(CineoPointerSidecar.self, from: data)
        #expect(decoded.cursorMode == .embedded)
        #expect(decoded.schemaVersion == 1)
    }
}
