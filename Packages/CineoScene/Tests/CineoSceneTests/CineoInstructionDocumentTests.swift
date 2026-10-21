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

    @Test func manualCameraRoundTripIsExactlyEquivalent() throws {
        let plan = CineoScenePlan(
            outputWidth: 1080, outputHeight: 1920,
            paddingFraction: 0.105,
            background: .init(red: 0.015, green: 0.017, blue: 0.025),
            camera: [
                .init(time: 0, zoom: 1, focusX: 0.5, focusY: 0.5),
                .init(time: 1.7, zoom: 1.73, focusX: 0.81, focusY: 0.27),
                .init(time: 2.8, zoom: 2.7, focusX: 0.9, focusY: 0.11),
                .init(time: 6.1, zoom: 1, focusX: 0.5, focusY: 0.5)
            ]
        )
        let json = try CineoInstructionDocument.equivalentJSON(for: plan, duration: 10)
        #expect(json.contains("camera.keyframe"))
        let parsed = try CineoInstructionDocument.decode(Data(json.utf8))
        #expect(parsed.actions.count == 4)
        let restored = try parsed.compile(duration: 10, over: base)
        #expect(restored == plan)
        for time in stride(from: 0.0, through: 9.8, by: 0.2) {
            let before = try plan.evaluate(time: time, sourceWidth: 1512, sourceHeight: 982)
            let after = try restored.evaluate(time: time, sourceWidth: 1512, sourceHeight: 982)
            #expect(before == after)
        }
    }

    @Test func exportEmptyManualTimelineStillRoundTripsStage() throws {
        let plan = CineoScenePlan(
            outputWidth: 1920, outputHeight: 1080,
            paddingFraction: 0.09,
            background: .init(red: 0.91, green: 0.93, blue: 0.97),
            camera: []
        )
        let json = try CineoInstructionDocument.equivalentJSON(for: plan, duration: 8)
        let decoded = try CineoInstructionDocument.decode(Data(json.utf8))
        #expect(decoded.actions.isEmpty)
        #expect(try decoded.compile(duration: 8, over: base) == plan)
    }

    @Test func exactKeyframeImportRejectsEqualTimes() {
        let json = """
        {"version":1,"timebase":"output","actions":[
          {"id":"k1","type":"camera.keyframe","time":2,
           "target":{"x":0.5,"y":0.5},"scale":1},
          {"id":"k2","type":"camera.keyframe","time":2,
           "target":{"x":0.6,"y":0.4},"scale":1.6}
        ]}
        """
        #expect(throws: CineoInstructionError.self) { try compile(json) }
    }

    @Test func cannotMixDescriptiveZoomsAndExactKeyframes() {
        let json = """
        {"version":1,"timebase":"output","actions":[
          {"id":"shot","type":"camera.zoom","start":3,"end":6,
           "target":{"x":0.8,"y":0.3},"scale":1.5,
           "transition":{"in":0.4,"out":0.4}},
          {"id":"key","type":"camera.keyframe","time":8,
           "target":{"x":0.5,"y":0.5},"scale":1}
        ]}
        """
        #expect(throws: CineoInstructionError.self) { try compile(json) }
    }

    @Test func keyframeDoesNotAcceptZoomShotFields() {
        let json = """
        {"version":1,"timebase":"output","actions":[
          {"id":"key","type":"camera.keyframe","time":2, "end":3,
           "target":{"x":0.5,"y":0.5},"scale":1}
        ]}
        """
        #expect(throws: CineoInstructionError.self) { try compile(json) }
    }

    @Test func equivalenceFailsForUnrepresentableStage() {
        let unsupported = CineoScenePlan(
            outputWidth: 1440, outputHeight: 900,
            background: .init(red: 0.3, green: 0.4, blue: 0.5)
        )
        #expect(throws: CineoInstructionError.self) {
            try CineoInstructionDocument.equivalentJSON(for: unsupported, duration: 5)
        }
    }
    @Test func musicOnlyInstructionsPreserveCameraAndCompileWithSameTimeline() throws {
        let old = CineoScenePlan(outputWidth: 1920, outputHeight: 1080,
            camera: [.init(time: 2, zoom: 1.7, focusX: 0.7, focusY: 0.3)])
        let json = """
        {"version":1,"timebase":"output","actions":[],
         "music":{"type":"music.generate",
                  "caption":"Gentle analog synth instrumental","bpm":108,
                  "duration":30,"keyscale":"A minor","seed":8,
                  "volume":0.35,"offset":0,"fadeIn":0.5,"fadeOut":1.5}}
        """
        let document = try CineoInstructionDocument.decode(Data(json.utf8))
        #expect(document.music?.bpm == 108)
        let output = try document.compile(duration: 34, over: old)
        #expect(output == old)
    }

    @Test func musicRejectsUnknownFieldsAndInvalidBPM() {
        let extra = """
        {"version":1,"timebase":"output","actions":[],
         "music":{"type":"music.generate","caption":"abc","bpm":110,
                  "duration":20,"keyscale":"C major","seed":-1,
                  "volume":0.3,"offset":0,"fadeIn":1,"fadeOut":1,
                  "llmPrompt":"unexpected"}}
        """
        #expect(throws: CineoInstructionError.self) {
            try compile(extra, duration: 30)
        }
        let invalid = """
        {"version":1,"timebase":"output","actions":[],
         "music":{"type":"music.generate","caption":"abc","bpm":900,
                  "duration":20,"keyscale":"C major","seed":-1,
                  "volume":0.3,"offset":0,"fadeIn":1,"fadeOut":1}}
        """
        #expect(throws: CineoInstructionError.self) {
            try compile(invalid, duration: 30)
        }
    }

}
