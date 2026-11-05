import Foundation
import AVFoundation
import CoreVideo
import CryptoKit
import CineoVideoAnalysis
import CineoDirector
import CineoScene

/// Exploratory synthetic quality measurement. Non-gating until evaluated
/// against a diverse set of real, user-consented screen recordings.
@main
struct CineoImportedCursorBenchmark {
    static func main() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("cineo-cursor-benchmark-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let video = root.appendingPathComponent("synthetic-screen.mp4")
        try await generateVideo(video)
        let digestBefore = SHA256.hash(data: try Data(contentsOf: video))
        let asset = AVURLAsset(url: video)
        let duration = try await asset.load(.duration)
        let sourceSeconds = duration.seconds
        let sourceX = (85.0 + 2.7 * 2) / 640.0
        let sourceY = 120.0 / 360.0
        let report: CineoImportedPointerAnalysis?
        do {
            report = try await CineoVideoCursorTracker().analyze(
                videoURL: video, expectedSourceDuration: sourceSeconds,
                seedSourceSeconds: 0.05, hotspotX: sourceX, hotspotY: sourceY,
                samplesPerSecond: 6)
        } catch {
            report = nil
            print("QUALITY TRACKING INCONCLUSIVE: \(error)")
        }
        let digestAfter = SHA256.hash(data: try Data(contentsOf: video))
        guard digestBefore == digestAfter else {
            throw BenchmarkError.sourceModified
        }
        if let report {
            let known = report.samples.map { point -> Double in
                let frame = min(59, max(0, Int((point.sourceSeconds * 30).rounded())))
                let expectedX = 85.0 + 2.7 * Double(frame)
                let expectedY = 120.0
                return hypot(point.x * 640 - expectedX,
                             point.y * 360 - expectedY)
            }
            for sample in report.samples.prefix(14) {
                let frame = min(59, max(0, Int((sample.sourceSeconds * 30).rounded())))
                let expectedX = 85.0 + 2.7 * Double(frame)
                print(String(format: "CURSOR_POINT time=%.2f x=%.1f y=%.1f refX=%.1f refY=120.0 confidence=%.2f",
                             sample.sourceSeconds, sample.x * 640, sample.y * 360,
                             expectedX, sample.confidence))
            }
            let avg = known.reduce(0, +) / Double(known.count)
            let highQuality = report.samples.filter { $0.confidence >= 0.65 }.count
            let lastTracked = report.samples.last?.sourceSeconds ?? 0
            let coverage = Double(known.count) / 12.0
            print(String(format: "CURSOR_BENCHMARK samples=%d confident=%d meanErrorPx=%.2f maxErrorPx=%.2f coverage=%.2f lastTracked=%.2f",
                         known.count, highQuality, avg, known.max() ?? 0, coverage, lastTracked))
            guard known.count >= 9, highQuality >= 8,
                  avg <= 8, (known.max() ?? .infinity) <= 16 else {
                throw BenchmarkError.qualityFailed
            }
        } else {
            print("CURSOR_BENCHMARK samples=0 confident=0 result=lost-track")
            throw BenchmarkError.qualityFailed
        }
        // Full local pipeline: inferred dwell -> editable camera keyframes ->
        // actual Core Image H264 output. This uses explicitly simulated
        // position observations so tracking correctness and edit correctness
        // are tested independently instead of conflating failures.
        let stable = (1...10).map { index in
            CineoImportedPointerSample(
                sourceSeconds: Double(index) * 0.1,
                x: 0.68, y: 0.36, confidence: 0.95)
        }
        let inferred = try CineoImportedPointerAnalysis(
            sourceDuration: sourceSeconds, seedSourceSeconds: 0.1,
            samples: stable)
        let suggestion = CineoImportedVideoAttentionPlanner().propose(
            analysis: inferred, outputDuration: sourceSeconds,
            cutMapper: { $0 }, preset: .balanced)
        guard suggestion.shots.count == 1,
              suggestion.keyframes.count == 4
        else { throw BenchmarkError.noAttentionShot }
        let rendered = root.appendingPathComponent("imported-smartcamera.mp4")
        let scene = CineoScenePlan(outputWidth: 320, outputHeight: 180,
                                   paddingFraction: 0.08,
                                   camera: suggestion.keyframes)
        try scene.validate()
        try await CineoSceneExporter().export(
            source: video, destination: rendered, plan: scene)
        let assetOut = AVURLAsset(url: rendered)
        guard let outTrack = try await assetOut.loadTracks(withMediaType: .video).first
        else { throw BenchmarkError.invalidExport }
        let outDuration = try await assetOut.load(.duration)
        let outSize = try await outTrack.load(.naturalSize)
        guard abs(outDuration.seconds - sourceSeconds) < 0.35,
              outSize.width == 320, outSize.height == 180,
              SHA256.hash(data: try Data(contentsOf: video)) == digestBefore
        else { throw BenchmarkError.invalidExport }
        print("PASS: inferred dwell -> editable Smart Camera keyframes -> real H264 320x180")
        print("PASS: synthetic H264 cursor accuracy and original source SHA unchanged")
    }

    enum BenchmarkError: Error { case writerFailed, sourceModified, qualityFailed, noAttentionShot, invalidExport }

    static func generateVideo(_ url: URL) async throws {
        let width = 640, height = 360
        let writer = try AVAssetWriter(outputURL: url, fileType: .mp4)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: width,
            AVVideoHeightKey: height,
            AVVideoCompressionPropertiesKey: [AVVideoAverageBitRateKey: 1_000_000]
        ])
        input.expectsMediaDataInRealTime = false
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: input,
            sourcePixelBufferAttributes: [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
                kCVPixelBufferWidthKey as String: width,
                kCVPixelBufferHeightKey as String: height,
                kCVPixelBufferIOSurfacePropertiesKey as String: [:] as [String: Any]
            ])
        writer.add(input)
        guard writer.startWriting() else { throw BenchmarkError.writerFailed }
        writer.startSession(atSourceTime: .zero)
        for frame in 0..<60 {
            guard let pool = adaptor.pixelBufferPool else { throw BenchmarkError.writerFailed }
            var result: CVPixelBuffer?
            guard CVPixelBufferPoolCreatePixelBuffer(kCFAllocatorDefault, pool, &result) == kCVReturnSuccess,
                  let pixel = result else { throw BenchmarkError.writerFailed }
            paint(pixel, width: width, height: height, cursorX: 85 + Int(2.7 * Double(frame)),
                  cursorY: 120)
            while !input.isReadyForMoreMediaData {
                try await Task.sleep(for: .milliseconds(4))
            }
            guard adaptor.append(pixel, withPresentationTime: CMTime(value: Int64(frame), timescale: 30))
            else { throw BenchmarkError.writerFailed }
        }
        input.markAsFinished()
        await writer.finishWriting()
        guard writer.status == .completed else { throw BenchmarkError.writerFailed }
    }

    static func paint(_ pixel: CVPixelBuffer, width: Int, height: Int,
                      cursorX: Int, cursorY: Int) {
        CVPixelBufferLockBaseAddress(pixel, [])
        defer { CVPixelBufferUnlockBaseAddress(pixel, []) }
        guard let pointer = CVPixelBufferGetBaseAddress(pixel) else { return }
        let address = pointer.assumingMemoryBound(to: UInt8.self)
        let stride = CVPixelBufferGetBytesPerRow(pixel)
        for y in 0..<height {
            for x in 0..<width {
                let index = y * stride + x * 4
                let navBar = y < 48
                let panel = x > 50 && x < 575 && y > 73 && y < 310
                let button = x > 330 && x < 492 && y > 200 && y < 251
                let channel: UInt8 = navBar ? 40 : (button ? 126 : (panel ? 232 : 250))
                address[index] = channel
                address[index + 1] = navBar ? 55 : channel
                address[index + 2] = navBar ? 70 : channel
                address[index + 3] = 255
            }
        }
        // High-contrast macOS-like arrow: black border, white inside.
        // The annotated hotspot is the upper-left tip at cursorX/cursorY.
        for dy in 0..<22 {
            for dx in 0...min(12, dy * 2 / 3) {
                let x = cursorX + dx, y = cursorY + dy
                guard x >= 0, x < width, y >= 0, y < height else { continue }
                let edge = dx == 0 || dx == min(12, dy * 2 / 3) || dy == 21
                let color: UInt8 = edge ? 12 : 255
                let index = y * stride + x * 4
                address[index] = color
                address[index + 1] = color
                address[index + 2] = color
                address[index + 3] = 255
            }
        }
    }
}
