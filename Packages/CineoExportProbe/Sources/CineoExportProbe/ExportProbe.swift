import AVFoundation
import CoreMedia
import Foundation

/// A read-only media-structure probe for future P1/P3 physical-Mac exports.
/// It does NOT measure visual quality or infer whether recordings happened.
@main
struct ExportProbe {
    static func main() async {
        do {
            let args = try parse(Array(CommandLine.arguments.dropFirst()))
            let result = try await inspect(args)
            let data = try JSONSerialization.data(withJSONObject: result, options: [.prettyPrinted, .sortedKeys])
            FileHandle.standardOutput.write(data)
            FileHandle.standardOutput.write(Data([10]))
        } catch {
            let message = "Cineo export probe FAIL: \(error.localizedDescription)\n"
            FileHandle.standardError.write(Data(message.utf8))
            Foundation.exit(1)
        }
    }

    struct Inputs {
        let file: URL
        let width: Int
        let height: Int
        let minimumSeconds: Double
        let requireAudio: Bool
        let codec: String
    }

    enum ProbeError: LocalizedError {
        case invalidArguments
        case invalidMedia(String)

        var errorDescription: String? {
            switch self {
            case .invalidArguments:
                return "Expected --file <MP4> --width <pixels> --height <pixels> [--min-seconds <seconds>] [--require-audio] [--codec h264|hevc]."
            case .invalidMedia(let reason):
                return reason
            }
        }
    }

    static func parse(_ arguments: [String]) throws -> Inputs {
        var i = 0
        var values: [String: String] = [:]
        var requireAudio = false
        while i < arguments.count {
            let key = arguments[i]
            if key == "--require-audio" {
                requireAudio = true
                i += 1
                continue
            }
            guard ["--file", "--width", "--height", "--min-seconds", "--codec"].contains(key),
                  i + 1 < arguments.count, values[key] == nil
            else { throw ProbeError.invalidArguments }
            values[key] = arguments[i + 1]
            i += 2
        }
        guard let file = values["--file"], !file.isEmpty,
              let width = values["--width"].flatMap(Int.init), width > 0,
              let height = values["--height"].flatMap(Int.init), height > 0,
              let minimum = Double(values["--min-seconds"] ?? "0.1"), minimum.isFinite, minimum > 0,
              ["h264", "hevc"].contains(values["--codec"] ?? "h264")
        else { throw ProbeError.invalidArguments }

        return Inputs(file: URL(fileURLWithPath: file), width: width, height: height,
                      minimumSeconds: minimum, requireAudio: requireAudio, codec: values["--codec"] ?? "h264")
    }

    static func inspect(_ input: Inputs) async throws -> [String: Any] {
        guard FileManager.default.fileExists(atPath: input.file.path) else {
            throw ProbeError.invalidMedia("File does not exist.")
        }
        let asset = AVURLAsset(url: input.file)
        let duration = CMTimeGetSeconds(try await asset.load(.duration))
        guard duration.isFinite && duration >= input.minimumSeconds else {
            throw ProbeError.invalidMedia("Duration shorter than the required minimum or invalid.")
        }
        let tracks = try await asset.loadTracks(withMediaType: .video)
        guard tracks.count == 1, let track = tracks.first else {
            throw ProbeError.invalidMedia("Expected exactly one readable video track.")
        }
        let size = try await track.load(.naturalSize)
        let transform = try await track.load(.preferredTransform)
        let frame = CGRect(origin: .zero, size: size).applying(transform).standardized
        let width = Int(frame.width.rounded())
        let height = Int(frame.height.rounded())
        guard width == input.width && height == input.height else {
            throw ProbeError.invalidMedia("Output dimensions \(width)×\(height) do not match \(input.width)×\(input.height).")
        }
        let formats = try await track.load(.formatDescriptions)
        let types = formats.map { CMFormatDescriptionGetMediaSubType($0) }
        let expectedCodec: Set<FourCharCode> = input.codec == "h264"
            ? [kCMVideoCodecType_H264]
            : [kCMVideoCodecType_HEVC]
        guard types.contains(where: { expectedCodec.contains($0) }) else {
            throw ProbeError.invalidMedia("Codec is not the expected \(input.codec).")
        }
        let audioTracks = try await asset.loadTracks(withMediaType: .audio)
        if input.requireAudio && audioTracks.isEmpty {
            throw ProbeError.invalidMedia("Audio was required but no audio track was found.")
        }
        let fps = try await track.load(.nominalFrameRate)
        return [
            "validation": "passed",
            "width": width,
            "height": height,
            "durationSeconds": duration,
            "codec": input.codec,
            "nominalFrameRate": fps,
            "audioTrackCount": audioTracks.count,
            "note": "Container/track checks only: not a visual, audio-sync or TCC verification."
        ]
    }
}
