import Foundation
import Testing
@testable import CineoScene

struct CineoInstructionDocumentTests {
    private var base: CineoScenePlan {
        CineoScenePlan(outputWidth: 1920, outputHeight: 1080,
                       paddingFraction: 0.06)
    }

    private func compile(_ json: String, duration: Double = 20,
                         existing: CineoScenePlan? = nil) throws -> CineoScenePlan {
        try CineoInstructionDocument.decode(Data(json.utf8))
            .compile(duration: duration, over: existing ?? base)
    }

    @Test func zoomCreatesArrivalHoldAndDepartureInSameScenePlan() throws {
        let plan = try compile("""
        {
          "version": 1, "timebase": "output",
          "stage": {"aspect":"9:16", "background":"light", "padding":0.08},
          "actions": [
            {"id":"focus-report", "type":"camera.zoom",
             "start":3, "end":7, "target":{"x":0.75,"y":0.25},
             "scale":1.8, "transition":{"in":0.4,"out":0.5}}
          ]
        }
        """)
        #expect(plan.outputWidth == 1080)
        #expect(plan.outputHeight == 1920)
        #expect(plan.paddingFraction == 0.08)
        #expect(plan.background.red > 0.5)
        #expect(plan.camera.count == 4)
        #expect(plan.camera.map(\.time) == [3, 3.4, 6.5, 7])
        let atHold = try plan.evaluate(time: 5, sourceWidth: 1512, sourceHeight: 982)
        #expect(abs(atHold.cropWidth - 1/1.8) < 1e-9)
        #expect(atHold.cropX >= 0)
        let after = try plan.evaluate(time: 8, sourceWidth: 1512, sourceHeight: 982)
        #expect(after.cropWidth == 1)
    }

    @Test func stageOnlyPreservesExistingCameraInEditorBaseButClearsByV1ImportContract() throws {
        let old = CineoScenePlan(outputWidth: 1920, outputHeight: 1080,
                                 camera: [.init(time: 1, zoom: 1.5, focusX: 0.2, focusY: 0.2)])
        let plan = try compile("""
          {"version":1, "timebase":"output", "stage":{"background":"black"}, "actions":[]}
          """, existing: old)
        #expect(plan.camera.isEmpty)
        #expect(plan.background.red < 0.04)
        #expect(plan.outputWidth == 1920)
    }

    @Test func unknownActionNeverSilentlyIgnored() {
        let json = """
        {"version":1,"timebase":"output","actions":[
          {"id":"callout","type":"text.callout","start":2,"end":5,
           "target":{"x":0.5,"y":0.5},"scale":1.5,
           "transition":{"in":0.4,"out":0.4}}
        ]}
        """
        #expect(throws: CineoInstructionError.self) {
            try compile(json)
        }
    }

    @Test func unknownFieldsAreRejectedBeforeChangingTheScene() {
        let json = """
        {"version":1,"timebase":"output","actions":[
          {"id":"zoom","type":"camera.zoom","start":2,"end":5,
           "text":"Ignored?","target":{"x":0.5,"y":0.5},"scale":1.5,
           "transition":{"in":0.4,"out":0.4}}
        ]}
        """
        #expect(throws: CineoInstructionError.self) {
            try compile(json)
        }
    }

    @Test func overlapIsRejectedEvenWithUnsortedInput() {
        let json = """
        {"version":1,"timebase":"output","actions":[
          {"id":"second","type":"camera.zoom","start":4,"end":8,
           "target":{"x":0.2,"y":0.2},"scale":1.5,"transition":{"in":0.4,"out":0.4}},
          {"id":"first","type":"camera.zoom","start":2,"end":5,
           "target":{"x":0.6,"y":0.6},"scale":1.5,"transition":{"in":0.4,"out":0.4}}
        ]}
        """
        #expect(throws: CineoInstructionError.self) { try compile(json) }
    }

    @Test func rejectsClipOverflowAndDuplicateIDs() {
        let overflow = """
        {"version":1,"timebase":"output","actions":[
          {"id":"last","type":"camera.zoom","start":18,"end":21,
           "target":{"x":0.5,"y":0.5},"scale":1.5,"transition":{"in":0.4,"out":0.4}}
        ]}
        """
        #expect(throws: CineoInstructionError.self) { try compile(overflow) }
        let duplicates = """
        {"version":1,"timebase":"output","actions":[
          {"id":"same","type":"camera.zoom","start":2,"end":4,
           "target":{"x":0.5,"y":0.5},"scale":1.5,"transition":{"in":0.4,"out":0.4}},
          {"id":"same","type":"camera.zoom","start":6,"end":8,
           "target":{"x":0.5,"y":0.5},"scale":1.5,"transition":{"in":0.4,"out":0.4}}
        ]}
        """
        #expect(throws: CineoInstructionError.self) { try compile(duplicates) }
    }

    @Test func strictCoordinateAndTransitionValidation() {
        let invalid = """
        {"version":1,"timebase":"output","actions":[
          {"id":"bad","type":"camera.zoom","start":2,"end":5,
           "target":{"x":1.1,"y":0.5},"scale":1.5,"transition":{"in":0.4,"out":0.4}}
        ]}
        """
        #expect(throws: CineoInstructionError.self) { try compile(invalid) }
    }

    @Test func unsupportedVersionAndTimebaseFail() {
        #expect(throws: CineoInstructionError.self) {
            try compile(#"{"version":2,"timebase":"output","stage":{"background":"dark"},"actions":[]}"#)
        }
        #expect(throws: CineoInstructionError.self) {
            try compile(#"{"version":1,"timebase":"source","stage":{"background":"dark"},"actions":[]}"#)
        }
    }
}
