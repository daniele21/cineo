import Foundation
import Testing
@testable import CineoScene

struct CineoSceneTests {
    @Test func identityStageBoundsAndDeterminism() throws {
        let plan = CineoScenePlan(outputWidth: 1920, outputHeight: 1080)
        let a = try plan.evaluate(time: 2, sourceWidth: 1512, sourceHeight: 982)
        let b = try plan.evaluate(time: 2, sourceWidth: 1512, sourceHeight: 982)
        #expect(a == b)
        #expect(a.cropX == 0)
        #expect(a.cropY == 0)
        #expect(a.cropWidth == 1)
        #expect(a.outputWidth <= 1920)
        #expect(a.outputHeight <= 1080)
    }

    @Test func smoothCameraStaysInsideSource() throws {
        let plan = CineoScenePlan(
            outputWidth: 1920, outputHeight: 1080,
            camera: [.init(time: 0, zoom: 1, focusX: 0.5, focusY: 0.5),
                     .init(time: 5, zoom: 1.8, focusX: 0.98, focusY: 0.02),
                     .init(time: 10, zoom: 1, focusX: 0.5, focusY: 0.5)]
        )
        for step in 0...100 {
            let state = try plan.evaluate(time: Double(step) / 10,
                                          sourceWidth: 1512, sourceHeight: 982)
            #expect(state.cropX >= 0)
            #expect(state.cropY >= 0)
            #expect(state.cropX + state.cropWidth <= 1.000001)
            #expect(state.cropY + state.cropHeight <= 1.000001)
            #expect(state.outputWidth > 0)
        }
        let zoom = try plan.evaluate(time: 5, sourceWidth: 1512, sourceHeight: 982)
        #expect(abs(zoom.cropWidth - 1 / 1.8) < 1e-9)
    }

    @Test func invalidPlanRejected() {
        let bad = CineoScenePlan(outputWidth: 1919, outputHeight: 1080)
        #expect(throws: CineoSceneError.invalidPlan) {
            try bad.evaluate(time: 0, sourceWidth: 1920, sourceHeight: 1080)
        }
    }
}
