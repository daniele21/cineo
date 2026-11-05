import Foundation
import AVFoundation
import CoreVideo
import CryptoKit
import CineoVideoAnalysis

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
            let avg = known.reduce(0, +) / Double(known.count)
            let highQuality = report.samples.filter { $0.confidence >= 0.65 }.count
            print(String(format: "CURSOR_BENCHMARK samples=%d confident=%d meanErrorPx=%.2f maxErrorPx=%.2f",
                         known.count, highQuality, avg, known.max() ?? 0))
        } else {
            print("CURSOR_BENCHMARK samples=0 confident=0 result=lost-track")
        }
        print("PASS: deterministic synthetic fixture created and source SHA unchanged")
    }

    enum BenchmarkError: Error { case writerFailed, sourceModified }

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
