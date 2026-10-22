import Foundation
import AVFoundation
import CoreVideo
import AudioToolbox
import CineoAudio
import CineoMusic

@main
struct CineoAudioSmoke {
    static func main() async throws {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("cineo-audio-smoke-" + UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }

        let video = folder.appendingPathComponent("synthetic-video.mp4")
        let music = folder.appendingPathComponent("synthetic-music.wav")
        let silence = folder.appendingPathComponent("silent-narration.wav")
        let voice = folder.appendingPathComponent("active-narration.wav")
        let ducked = folder.appendingPathComponent("ducked.mp4")
        let withVoice = folder.appendingPathComponent("voice-and-music.mp4")
        print("[audio-smoke] Generate 3.6s synthetic H264 and deterministic PCM fixtures")
        try await makeVideo(url: video)
        try makeWAV(url: music, duration: 1.2, frequency: 220, activity: { _ in true })
        try makeWAV(url: silence, duration: 3.6, frequency: 440, activity: { _ in false })
        try makeWAV(url: voice, duration: 3.6, frequency: 440,
                    activity: { $0 >= 1.25 && $0 < 2.15 })
        let settings = CineoMusicSettings(
            caption: "test", bpm: 100, duration: 10,
            keyscale: "C major", volume: 0.65, offset: 0, fadeIn: 0, fadeOut: 0)
        let clip = CineoMusicClip(sourceIn: 0, duration: 3.6,
                                  loop: true, loopCrossfade: 0.2)
        let ducking = CineoDuckingSettings(enabled: true, level: 0.2,
                                          threshold: 0.08, attack: 0.1, release: 0.1)
        let active = [CineoAudioActivityRange(start: 1.25, end: 2.15)]

        print("[audio-smoke] Export video + true A/B audio overlap + duck envelope")
        try await CineoAudioMuxer.mux(video: video, original: silence, music: music,
                    settings: settings, clip: clip, ducking: ducking,
                    duckingRanges: active, destination: ducked)
        try await verifyMedia(url: ducked)
        let loud = try await rms(url: ducked, start: 0.6, end: 0.85)
        let reduced = try await rms(url: ducked, start: 1.55, end: 1.8)
        let recovered = try await rms(url: ducked, start: 2.9, end: 3.2)
        guard loud > 0.04, reduced > 0.003,
              reduced < loud * 0.43, recovered > reduced * 2.0 else {
            throw SmokeError.failed(String(format:
                "Ducking/loop mismatch: loud %.4f, reduced %.4f, recovered %.4f",
                loud, reduced, recovered))
        }
        print(String(format: "[audio-smoke] PASS: audible %.4f, ducked %.4f, recovered %.4f",
                     loud, reduced, recovered))

        print("[audio-smoke] Export again retaining non-silent original narration")
        try await CineoAudioMuxer.mux(video: video, original: voice, music: music,
                    settings: settings, clip: clip, ducking: ducking,
                    duckingRanges: active, destination: withVoice)
        try await verifyMedia(url: withVoice)
        let mixed = try await rms(url: withVoice, start: 1.55, end: 1.8)
        guard mixed > reduced * 1.7 else {
            throw SmokeError.failed(String(format:
                "Original narration lost: mixed %.4f vs ducked %.4f", mixed, reduced))
        }
        print(String(format: "[audio-smoke] PASS: original audio retained (RMS %.4f)", mixed))
        print("[audio-smoke] PASS: real AVFoundation/H264/AAC mux, loop and ducking")
    }

    private enum SmokeError: Error {
        case failed(String)
    }

    static func makeVideo(url: URL) async throws {
        let writer = try AVAssetWriter(outputURL: url, fileType: .mp4)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: 320,
            AVVideoHeightKey: 180
        ])
        input.expectsMediaDataInRealTime = false
        guard writer.canAdd(input) else { throw SmokeError.failed("Cannot add video input") }
        writer.add(input)
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input,
            sourcePixelBufferAttributes: [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
                kCVPixelBufferWidthKey as String: 320,
                kCVPixelBufferHeightKey as String: 180
            ])
        guard writer.startWriting() else {
            throw writer.error ?? SmokeError.failed("Video writer could not start")
        }
        writer.startSession(atSourceTime: .zero)
        guard let pool = adaptor.pixelBufferPool else {
            throw SmokeError.failed("Missing video pixel buffer pool")
        }
        for frame in 0..<72 {
            while !input.isReadyForMoreMediaData {
                try await Task.sleep(for: .milliseconds(10))
            }
            var pixel: CVPixelBuffer?
            guard CVPixelBufferPoolCreatePixelBuffer(kCFAllocatorDefault, pool, &pixel) == kCVReturnSuccess,
                  let buffer = pixel else {
                throw SmokeError.failed("Could not allocate source video frame")
            }
            CVPixelBufferLockBaseAddress(buffer, [])
            if let base = CVPixelBufferGetBaseAddress(buffer) {
                memset(base, Int32(40 + (frame % 50)), CVPixelBufferGetDataSize(buffer))
            }
            CVPixelBufferUnlockBaseAddress(buffer, [])
            guard adaptor.append(buffer, withPresentationTime: CMTime(value: CMTimeValue(frame),
                                                                      timescale: 20)) else {
                throw writer.error ?? SmokeError.failed("Cannot write H264 source frame")
            }
        }
        input.markAsFinished()
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            writer.finishWriting { continuation.resume() }
        }
        guard writer.status == .completed else {
            throw writer.error ?? SmokeError.failed("Synthetic video writer failed")
        }
    }

    static func makeWAV(url: URL, duration: Double, frequency: Double,
                        activity: (Double) -> Bool) throws {
        let sampleRate = 44_100
        let frames = Int(duration * Double(sampleRate))
        var pcm = Data(capacity: frames * 2)
        for i in 0..<frames {
            let time = Double(i) / Double(sampleRate)
            let sample = activity(time) ? 0.5 * sin(2 * .pi * frequency * time) : 0
            var value = Int16((sample * 32767).rounded()).littleEndian
            withUnsafeBytes(of: &value) { pcm.append(contentsOf: $0) }
        }
        var wav = Data()
        func add<T: FixedWidthInteger>(_ raw: T) {
            var value = raw.littleEndian
            withUnsafeBytes(of: &value) { wav.append(contentsOf: $0) }
        }
        wav.append(contentsOf: Array("RIFF".utf8))
        add(UInt32(36 + pcm.count))
        wav.append(contentsOf: Array("WAVEfmt ".utf8))
        add(UInt32(16))
        add(UInt16(1))
        add(UInt16(1))
        add(UInt32(sampleRate))
        add(UInt32(sampleRate * 2))
        add(UInt16(2))
        add(UInt16(16))
        wav.append(contentsOf: Array("data".utf8))
        add(UInt32(pcm.count))
        wav.append(pcm)
        try wav.write(to: url, options: .atomic)
    }

    static func verifyMedia(url: URL) async throws {
        let asset = AVURLAsset(url: url)
        let video = try await asset.loadTracks(withMediaType: .video)
        let audio = try await asset.loadTracks(withMediaType: .audio)
        let length = try await asset.load(.duration)
        guard !video.isEmpty, !audio.isEmpty,
              abs(length.seconds - 3.6) < 0.15 else {
            throw SmokeError.failed("Missing H264, AAC or 3.6s duration in exported MP4")
        }
    }

    static func rms(url: URL, start: Double, end: Double) async throws -> Double {
        let asset = AVURLAsset(url: url)
        guard let track = try await asset.loadTracks(withMediaType: .audio).first else {
            throw SmokeError.failed("Missing audio track in \(url.lastPathComponent)")
        }
        let reader = try AVAssetReader(asset: asset)
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: 44_100.0,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 32,
            AVLinearPCMIsFloatKey: true,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsNonInterleaved: false
        ])
        reader.add(output)
        guard reader.startReading() else {
            throw reader.error ?? SmokeError.failed("Cannot read exported PCM")
        }
        defer { if reader.status == .reading { reader.cancelReading() } }
        var energy = 0.0
        var count = 0
        while let buffer = output.copyNextSampleBuffer() {
            let time = CMSampleBufferGetPresentationTimeStamp(buffer).seconds
            guard let data = CMSampleBufferGetDataBuffer(buffer) else { continue }
            let byteLength = CMBlockBufferGetDataLength(data)
            guard byteLength > 0, byteLength % 4 == 0 else { continue }
            var chunk = Data(count: byteLength)
            let code = chunk.withUnsafeMutableBytes { bytes in
                CMBlockBufferCopyDataBytes(data, atOffset: 0, dataLength: byteLength,
                                           destination: bytes.baseAddress!)
            }
            guard code == noErr else { throw SmokeError.failed("PCM copy failed") }
            chunk.withUnsafeBytes { ptr in
                for i in 0..<(byteLength / 4) {
                    let t = time + Double(i) / 44_100
                    guard t >= start, t < end else { continue }
                    let x = Double(ptr.loadUnaligned(fromByteOffset: i * 4, as: Float.self))
                    if x.isFinite { energy += x * x; count += 1 }
                }
            }
        }
        guard count > 100 else { throw SmokeError.failed("Not enough decoded audio") }
        return sqrt(energy / Double(count))
    }
}
