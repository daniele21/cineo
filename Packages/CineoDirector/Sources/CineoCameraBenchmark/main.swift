import Foundation
import CineoDirector
import CineoEvents
import CineoScene

private struct Case: Decodable {
    let id: String
    let duration: Double
    let preset: CameraPreset
    let events: [CineoPointerEvent]
    let minShots: Int
    let maxShots: Int
}
private struct Result: Encodable {
    let fixture: String
    let preset: String
    let metrics: CineoCameraQualityMetrics
    let passed: Bool
}

enum CineoCameraBenchmark {
    static func main() throws {
        guard let source = Bundle.module.url(forResource: "autoedit-cases", withExtension: "json") else {
            throw NSError(domain: "CineoBenchmark", code: 1,
                          userInfo: [NSLocalizedDescriptionKey:"Fixtures are missing"])
        }
        let cases = try JSONDecoder().decode([Case].self, from: Data(contentsOf: source))
        var results: [Result] = []
        for fixture in cases {
            let sidecar = try CineoPointerSidecar(events: fixture.events)
            let planner = CineoAutoEditPlanner()
            let proposal = planner.propose(sidecar: sidecar, duration: fixture.duration,
                                           preset: fixture.preset)
            let metrics = CineoCameraQuality.measure(shots: proposal.shots,
                                                      duration: fixture.duration,
                                                      maxShotsPerMinute: fixture.preset.configuration.maxShotsPerMinute)
            let plan = CineoScenePlan(outputWidth: 1920, outputHeight: 1080,
                                      camera: proposal.keyframes)
            try plan.validate()
            let passed = metrics.isStructurallySafe &&
                         (fixture.minShots...fixture.maxShots).contains(proposal.shots.count) &&
                         proposal.keyframes.count == proposal.shots.count * 4
            results.append(Result(fixture: fixture.id, preset: fixture.preset.rawValue,
                                  metrics: metrics, passed: passed))
        }
        let report = JSONEncoder()
        report.outputFormatting = [.prettyPrinted, .sortedKeys]
        print(String(decoding: try report.encode(results), as: UTF8.self))
        if results.contains(where: { !$0.passed }) { exit(EXIT_FAILURE) }
    }
}

try CineoCameraBenchmark.main()
