import Testing
import CineoEvents
import CineoScene
@testable import CineoDirector

struct CineoAutoEditPlannerTests {
    @Test func emptyAndMovementOnlyHaveNoFabricatedZooms() throws {
        let source = try CineoPointerSidecar(events: [
            .init(sourceSeconds: 0.5, x: 0.1, y: 0.9, kind: .moved),
            .init(sourceSeconds: 1.5, x: 0.3, y: 0.8, kind: .scroll)
        ])
        #expect(CineoAutoEditPlanner().propose(sidecar: source, duration: 8).isEmpty)
    }

    @Test func clicksCreateBoundedEditableCameraKeyframes() throws {
        let source = try CineoPointerSidecar(events: [
            .init(sourceSeconds: 2, x: 0.2, y: 0.3, kind: .leftClick),
            .init(sourceSeconds: 2.2, x: 0.22, y: 0.32, kind: .leftClick),
            .init(sourceSeconds: 7, x: 0.8, y: 0.7, kind: .rightClick)
        ])
        let p = CineoAutoEditPlanner().propose(sidecar: source, duration: 12)
        #expect(p.shots.count == 2)
        #expect(p.keyframes.count == p.shots.count * 4)
        #expect(p.keyframes.allSatisfy { $0.time >= 0 && $0.time <= 12 })
        let scene = CineoScenePlan(outputWidth: 1920, outputHeight: 1080, camera: p.keyframes)
        try scene.validate()
        #expect(p.keyframes[0].zoom == 1)
        #expect(p.keyframes[3].zoom == 1)
        #expect(p.keyframes[1].zoom > 1)
    }

    @Test func shotOrderIsDeterministic() throws {
        let s = try CineoPointerSidecar(events: [
            .init(sourceSeconds: 3, x: 0.5, y: 0.5, kind: .leftClick),
            .init(sourceSeconds: 9, x: 0.1, y: 0.3, kind: .leftClick)
        ])
        let director = CineoAutoEditPlanner()
        let a = director.propose(sidecar: s, duration: 14)
        let b = director.propose(sidecar: s, duration: 14)
        #expect(a.keyframes == b.keyframes)
    }
}
