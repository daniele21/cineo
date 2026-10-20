import Foundation
import CineoScene

@main
struct CineoSceneSpike {
    static func main() async {
        let args = Array(CommandLine.arguments.dropFirst())
        guard args.count == 2 else {
            FileHandle.standardError.write(Data("Usage: cineo-scene-spike INPUT.mp4 OUTPUT.mp4\n".utf8))
            exit(2)
        }
        let input = URL(fileURLWithPath: args[0])
        let output = URL(fileURLWithPath: args[1])
        let plan = CineoScenePlan(outputWidth: 1920, outputHeight: 1080,
                                  camera: [
                                    .init(time: 0, zoom: 1, focusX: 0.5, focusY: 0.5),
                                    .init(time: 5, zoom: 1.45, focusX: 0.7, focusY: 0.45),
                                    .init(time: 10, zoom: 1, focusX: 0.5, focusY: 0.5)
                                  ])
        #if canImport(AVFoundation) && canImport(CoreImage)
        do {
            try await CineoSceneExporter().export(source: input, destination: output, plan: plan) {
                value in
                let percent = Int(value * 100)
                if percent % 5 == 0 {
                    FileHandle.standardError.write(Data(("render " + String(percent) + "%\n").utf8))
                }
            }
            print("MP4 verified: \(output.path)")
        } catch {
            FileHandle.standardError.write(Data(("Render failed: \(error)\n").utf8))
            exit(1)
        }
        #else
        FileHandle.standardError.write(Data("This renderer requires macOS AVFoundation/Core Image.\n".utf8))
        exit(2)
        #endif
    }
}
