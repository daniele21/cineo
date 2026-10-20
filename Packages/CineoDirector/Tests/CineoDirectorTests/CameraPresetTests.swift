import Foundation
import Testing
@testable import CineoDirector

struct CameraPresetTests {
    private let events: [AttentionEvent] = [
        .init(time: 2.0, x: 0.5, y: 0.5, kind: .click),
        .init(time: 2.1, x: 0.5, y: 0.5, kind: .click),
        .init(time: 11.0, x: 0.8, y: 0.4, kind: .result)
    ]

    @Test func namesAndRawValuesAreStableForPresetSerialization() throws {
        #expect(CameraPreset.allCases.count == 3)
        #expect(try JSONDecoder().decode(CameraPreset.self, from: Data(#""balanced""#.utf8)) == .balanced)
        #expect(CameraPreset.subtle.displayName == "Subtle")
    }

    @Test func eachPresetUsesDifferentBoundedScale() {
        let shots = CameraPreset.allCases.map {
            CameraPlanner(configuration: $0.configuration).suggest(events: events, duration: 18)
        }
        #expect(shots.allSatisfy { $0.count == 2 })
        #expect(shots[0][0].zoom < shots[1][0].zoom)
        #expect(shots[1][0].zoom < shots[2][0].zoom)
        #expect(shots[0][1].reason == .result)
        #expect(shots[0][1].zoom < shots[2][1].zoom)
    }

    @Test func allPresetsProduceSafeNonoverlappingTimeline() {
        let burst = (0..<60).map { i in
            AttentionEvent(time: Double(i) * 0.5 + 1,
                           x: i.isMultiple(of: 2) ? 0.2 : 0.8,
                           y: 0.5, kind: .click)
        }
        for preset in CameraPreset.allCases {
            let shots = CameraPlanner(configuration: preset.configuration)
                .suggest(events: burst, duration: 45)
            #expect(shots.allSatisfy { $0.start >= 0 && $0.end <= 45 && $0.end > $0.start })
            for i in shots.indices.dropFirst() {
                #expect(shots[i].start >= shots[i-1].end)
            }
            #expect(shots.count <= preset.configuration.maxShotsPerMinute)
        }
    }

    @Test func repeatGenerationIsDeterministic() {
        for preset in CameraPreset.allCases {
            let planner = CameraPlanner(configuration: preset.configuration)
            #expect(planner.suggest(events: events, duration: 18) ==
                    planner.suggest(events: events.reversed(), duration: 18))
        }
    }
}
