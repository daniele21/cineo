import Foundation
import Testing
import CineoEvents
import CineoScene
@testable import CineoDirector

struct CineoCameraFollowPlannerTests {
    private func sampleScene() -> CineoScenePlan {
        CineoScenePlan(outputWidth: 1920, outputHeight: 1080,
            camera: [
                .init(time: 0, zoom: 1, focusX: 0.5, focusY: 0.5),
                .init(time: 1, zoom: 2, focusX: 0.5, focusY: 0.5),
                .init(time: 5, zoom: 2, focusX: 0.5, focusY: 0.5),
                .init(time: 6, zoom: 1, focusX: 0.5, focusY: 0.5)
            ])
    }
    @Test func followsOnlyWhenPointerEscapesInnerSafeZone() throws {
        let plan = sampleScene()
        let planner = CineoCameraFollowPlanner()
        let quiet = try planner.propose(base: plan,
            movements: (0..<15).map { index in
                .init(sourceSeconds: 2 + Double(index) * 0.1,
                      x: 0.52, y: 0.48, kind: .moved)
            }, duration: 7)
        #expect(quiet == plan.camera)
        let moving = try planner.propose(base: plan, movements: [
            .init(sourceSeconds: 2.0, x: 0.94, y: 0.8, kind: .moved),
            .init(sourceSeconds: 2.5, x: 0.96, y: 0.8, kind: .moved)
        ], duration: 7)
        #expect(moving.count > plan.camera.count)
        #expect(moving.contains(where: { $0.time == 2 && $0.focusX > 0.5 }))
        #expect(try CineoScenePlan(outputWidth: 1920, outputHeight: 1080,
            camera: moving).evaluate(time: 2, sourceWidth: 1512, sourceHeight: 982).cropX >= 0)
    }

    @Test func neverOverwritesOriginalZoomKeyframesOrCreatesStorms() throws {
        let plan = sampleScene()
        let movements = (0..<3000).map { i in
            CineoPointerEvent(sourceSeconds: 0.2 + Double(i) * 0.002,
                 x: i.isMultiple(of: 2) ? 0.97 : 0.03, y: 0.99, kind: .moved)
        }
        let follow = try CineoCameraFollowPlanner().propose(base: plan,
            movements: movements, duration: 7)
        #expect(follow.count < 55)
        for original in plan.camera {
            #expect(follow.contains(original))
        }
        let again = try CineoCameraFollowPlanner().propose(base: plan,
            movements: movements.reversed(), duration: 7)
        #expect(follow == again)
    }

    @Test func doesNotInventMovementFromClicks() throws {
        let plan = sampleScene()
        let result = try CineoCameraFollowPlanner().propose(base: plan, movements: [
            .init(sourceSeconds: 2, x: 0.99, y: 0.99, kind: .leftClick)
        ], duration: 7)
        #expect(result == plan.camera)
    }
}
