import Foundation
import Testing
@testable import CineoScene

struct CineoSceneMotionCurveTests {
    @Test func classicIsLegacySmoothstep() {
        for step in 0...100 {
            let x = Double(step) / 100
            #expect(CineoSceneMotionCurve.progress(x) == x * x * (3 - 2 * x))
        }
    }

    @Test func profilesAreBoundedMonotoneAndSeekOrderIndependent() {
        let samples = [0.0, 0.12, 0.27, 0.48, 0.61, 0.95, 1.0]
        for preset in CineoSceneMotionPreset.allCases {
            let forward = samples.map { CineoSceneMotionCurve.progress($0, preset: preset) }
            let reverse = samples.reversed().map { CineoSceneMotionCurve.progress($0, preset: preset) }
            #expect(forward == Array(reverse.reversed()))
            #expect(forward.first == 0)
            #expect(forward.last == 1)
            #expect(zip(forward, forward.dropFirst()).allSatisfy { $0.0 <= $0.1 })
            #expect(forward.allSatisfy { (0...1).contains($0) })
        }
        #expect(CineoSceneMotionCurve.progress(.nan) == 0)
        #expect(CineoSceneMotionCurve.progress(-1, preset: .focused) == 0)
        #expect(CineoSceneMotionCurve.progress(2, preset: .cinematic) == 1)
    }

    @Test func optionalPresetBackwardCompatibleWithOldScene() throws {
        let legacy = CineoScenePlan(outputWidth: 1920, outputHeight: 1080,
            camera: [
                .init(time: 0, zoom: 1, focusX: 0.5, focusY: 0.5),
                .init(time: 2, zoom: 2, focusX: 0.6, focusY: 0.5)
            ])
        let data = try JSONEncoder().encode(legacy)
        let decoded = try JSONDecoder().decode(CineoScenePlan.self, from: data)
        #expect(decoded.motionPreset == nil)
        #expect(try decoded.evaluate(time: 1, sourceWidth: 1920, sourceHeight: 1080) ==
                legacy.evaluate(time: 1, sourceWidth: 1920, sourceHeight: 1080))
        var upgraded = decoded
        upgraded.motionPreset = .cinematic
        let upgradedBytes = try JSONEncoder().encode(upgraded)
        #expect(try JSONDecoder().decode(CineoScenePlan.self, from: upgradedBytes) == upgraded)
    }
}
