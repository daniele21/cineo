import Foundation
import CineoProject
import CineoEditPlanner

/// CLT-only CLI. This first contract supports inspection, validation and
/// deterministic camera planning; H.264 rendering will be wired to *the same*
/// CineoScene exporter as the UI when its PR passes real-media tests.
@main
struct CineoCLI {
    static func main() {
        do {
            try run(Array(CommandLine.arguments.dropFirst()))
        } catch {
            let message = String(describing: error)
            FileHandle.standardError.write(Data(("cineo: " + message + "\n").utf8))
            exit(2)
        }
    }

    static func run(_ args: [String]) throws {
        guard args.count >= 2 else { throw CLIError.usage }
        let command = args[0]
        let projectPath = URL(fileURLWithPath: args[1], isDirectory: true)
        let project = try CineoProjectStore().load(from: projectPath)
        let duration = try TimelineMapper.outputDuration(for: project)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        switch command {
        case "validate", "inspect":
            let info = ProjectInfo(
                schemaVersion: project.schemaVersion,
                projectID: project.projectID.uuidString,
                sourceCount: project.sources.count,
                clipCount: project.edits.count,
                outputWidth: project.canvas.width,
                outputHeight: project.canvas.height,
                durationSeconds: duration
            )
            print(String(decoding: try encoder.encode(info), as: UTF8.self))
        case "plan":
            // No events => conservative NO-ZOOM output. Never fabricate clicks
            // from a source MP4 which has no separate time-coded sidecar.
            let suggestion = try CineoEditPlanner().suggest(for: project, events: [])
            try suggestion.validate(against: project)
            print(String(decoding: try encoder.encode(suggestion), as: UTF8.self))
        case "render":
            throw CLIError.rendererNotIntegrated
        default:
            throw CLIError.usage
        }
    }

    struct ProjectInfo: Codable {
        let schemaVersion: Int
        let projectID: String
        let sourceCount: Int
        let clipCount: Int
        let outputWidth: Int
        let outputHeight: Int
        let durationSeconds: Double
    }

    enum CLIError: Error, CustomStringConvertible {
        case usage, rendererNotIntegrated
        var description: String {
            switch self {
            case .usage: return "usage: cineo inspect|validate|plan PROJECT.cineo (render awaits shared CineoScene integration)"
            case .rendererNotIntegrated: return "render unavailable: same-renderer CineoScene integration is not yet verified"
            }
        }
    }
}
