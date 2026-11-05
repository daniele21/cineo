import Foundation
import CineoScene
import CineoProject
import CineoEvents

#if canImport(AVFoundation) && canImport(CoreImage)
import AVFoundation
import CoreImage
import CoreVideo
import CryptoKit

@main
struct SceneSyntheticExportSmoke {
    static func main() async {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("cineo-render-smoke-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: folder) }
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let source = folder.appendingPathComponent("input.mp4")
            let output = folder.appendingPathComponent("styled.mp4")
            try await makeSource(source)
            let before = SHA256.hash(data: try Data(contentsOf: source))
            let plan = CineoScenePlan(outputWidth: 320, outputHeight: 180,
                                      paddingFraction: 0.10,
                                      camera: [
                                        .init(time: 0, zoom: 1, focusX: 0.5, focusY: 0.5),
                                        .init(time: 0.8, zoom: 1.4, focusX: 0.72, focusY: 0.5),
                                        .init(time: 1.4, zoom: 1, focusX: 0.5, focusY: 0.5)
                                      ])
            try await CineoSceneExporter().export(source: source, destination: output, plan: plan)
            let after = SHA256.hash(data: try Data(contentsOf: source))
            guard before == after else { throw SmokeError.changedSource }
            let original = AVURLAsset(url: source), rendered = AVURLAsset(url: output)
            let sourceDuration = try await original.load(.duration)
            let outputDuration = try await rendered.load(.duration)
            guard abs(sourceDuration.seconds - outputDuration.seconds) < 0.35,
                  let track = try await rendered.loadTracks(withMediaType: .video).first
            else { throw SmokeError.invalidOutput }
            let size = try await track.load(.naturalSize)
            guard size.width == 320, size.height == 180 else {
                throw SmokeError.invalidOutput
            }
            let reader = try AVAssetReader(asset: rendered)
            let decoder = AVAssetReaderTrackOutput(track: track, outputSettings: [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
            ])
            reader.add(decoder)
            guard reader.startReading(), decoder.copyNextSampleBuffer() != nil else {
                throw SmokeError.invalidOutput
            }
            reader.cancelReading()
            guard try Data(contentsOf: source) != Data(contentsOf: output) else {
                throw SmokeError.invalidOutput
            }
            // A second render follows an actual cut-list. It checks that
            // source remains bit-identical while decoded output gets shorter.
            let cutOutput = folder.appendingPathComponent("cut.mp4")
            let cuts = try CineoCutList(sourceDuration: sourceDuration.seconds)
                .removingOutputRange(start: 0.4, end: 0.8)
            try await CineoSceneExporter().export(
                source: source, destination: cutOutput, plan: plan, cuts: cuts)
            let cutAsset = AVURLAsset(url: cutOutput)
            let cutDuration = try await cutAsset.load(.duration)
            guard abs(cutDuration.seconds - cuts.outputDuration) < 0.15,
                  SHA256.hash(data: try Data(contentsOf: source)) == before else {
                throw SmokeError.invalidOutput
            }
            // Independently drawn cursor: use the exact same Core Image
            // compositor for a frame-level comparison and a real encoded MP4.
            let pointerSidecar = try CineoPointerSidecar(events: [
                .init(sourceSeconds: 0.0, x: 0.40, y: 0.45, kind: .moved),
                .init(sourceSeconds: 0.5, x: 0.45, y: 0.50, kind: .moved),
                .init(sourceSeconds: 0.7, x: 0.50, y: 0.55, kind: .moved),
                .init(sourceSeconds: 1.95, x: 0.70, y: 0.55, kind: .moved)
            ], cursorMode: .independentOverlay)
            let pointer = try CineoCursorOverlay(sidecar: pointerSidecar)
            let probe = CIImage(color: CIColor(red: 0.25, green: 0.45, blue: 0.6))
                .cropped(to: CGRect(x: 0, y: 0, width: 128, height: 80))
            let baseFrame = try CineoSceneFrameRenderer.compose(
                probe, at: 0.5, with: plan)
            let overlayFrame = try CineoSceneFrameRenderer.compose(
                probe, at: 0.5, with: plan, cursor: pointer,
                cursorSourceSeconds: 0.5)
            let context = CIContext(options: [.useSoftwareRenderer: true])
            let bounds = CGRect(x: 0, y: 0, width: 320, height: 180)
            func bytes(_ image: CIImage) -> [UInt8] {
                var data = [UInt8](repeating: 0, count: 320 * 180 * 4)
                data.withUnsafeMutableBytes { buffer in
                    if let base = buffer.baseAddress {
                        context.render(image, toBitmap: base, rowBytes: 320 * 4,
                                       bounds: bounds, format: .RGBA8,
                                       colorSpace: CGColorSpaceCreateDeviceRGB())
                    }
                }
                return data
            }
            guard bytes(baseFrame) != bytes(overlayFrame) else {
                throw SmokeError.invalidOutput
            }
            let pointerOutput = folder.appendingPathComponent("independent-pointer.mp4")
            try await CineoSceneExporter().export(
                source: source, destination: pointerOutput, plan: plan,
                cursor: pointer)
            let pointerAsset = AVURLAsset(url: pointerOutput)
            guard !(try await pointerAsset.loadTracks(withMediaType: .video)).isEmpty,
                  SHA256.hash(data: try Data(contentsOf: source)) == before else {
                throw SmokeError.invalidOutput
            }
            print("PASS: 2s H.264 styled/cut/cursor outputs, overlay pixels differ only when enabled; source SHA unchanged.")
        } catch {
            FileHandle.standardError.write(Data("FAIL synthetic render smoke: \(error)\n".utf8))
            exit(1)
        }
    }

    static func makeSource(_ url: URL) async throws {
        let writer = try AVAssetWriter(outputURL: url, fileType: .mp4)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: 128,
            AVVideoHeightKey: 80,
            AVVideoCompressionPropertiesKey: [AVVideoAverageBitRateKey: 250_000]
        ])
        input.expectsMediaDataInRealTime = false
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: input,
            sourcePixelBufferAttributes: [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
                kCVPixelBufferWidthKey as String: 128,
                kCVPixelBufferHeightKey as String: 80,
                kCVPixelBufferIOSurfacePropertiesKey as String: [:] as [String: Any]
            ]
        )
        writer.add(input)
        guard writer.startWriting() else { throw SmokeError.invalidSource }
        writer.startSession(atSourceTime: .zero)
        let ci = CIContext()
        for frame in 0..<60 {
            guard let pool = adaptor.pixelBufferPool else { throw SmokeError.invalidSource }
            var buffer: CVPixelBuffer?
            guard CVPixelBufferPoolCreatePixelBuffer(kCFAllocatorDefault, pool, &buffer) == kCVReturnSuccess,
                  let buffer else { throw SmokeError.invalidSource }
            let phase = Double(frame) / 59
            let content = CIImage(color: CIColor(red: phase, green: 0.8 - phase * 0.5, blue: 0.1))
                .cropped(to: CGRect(x: 0, y: 0, width: 128, height: 80))
            ci.render(content, to: buffer)
            while !input.isReadyForMoreMediaData {
                try await Task.sleep(for: .milliseconds(5))
            }
            guard adaptor.append(buffer, withPresentationTime: CMTime(value: Int64(frame), timescale: 30)) else {
                throw SmokeError.invalidSource
            }
        }
        input.markAsFinished()
        await writer.finishWriting()
        guard writer.status == .completed else { throw SmokeError.invalidSource }
    }

    enum SmokeError: Error {
        case invalidSource, invalidOutput, changedSource
    }
}
#else
@main struct Unsupported {
    static func main() { print("Only macOS supports native media smoke.") }
}
#endif
