import Foundation
import AVFoundation
import CineoMusic

/// Offline AVFoundation PCM decoding. Shared between waveform/onset analysis
/// and original-recording audio activity (the latter is NOT speech detection).
enum CineoMusicAudioAnalyzer {
    static func analyze(url: URL) async throws -> CineoBeatAnalysis {
        let (samples, rate) = try await readPCM(url: url, maxSeconds: 600)
        return CineoBeatAnalyzer.analyze(samples: samples, sampleRate: rate)
    }

    static func activity(url: URL, thresholdDB: Double) async throws -> [CineoAudioActivity] {
        let (samples, rate) = try await readPCM(url: url, maxSeconds: 600)
        return CineoAudioDynamics.detectActivity(samples: samples, sampleRate: rate,
                                                 thresholdDB: thresholdDB)
    }

    private static func readPCM(url: URL, maxSeconds: Double) async throws -> ([Float], Double) {
        let asset = AVURLAsset(url: url)
        guard let track = try await asset.loadTracks(withMediaType: .audio).first else {
            throw CineoMusicError.invalid("La sorgente non contiene una traccia audio.")
        }
        let sourceLength = try await asset.load(.duration)
        let seconds = min(maxSeconds, max(0, sourceLength.seconds))
        guard seconds.isFinite && seconds > 0 else {
            throw CineoMusicError.invalid("Durata audio non disponibile.")
        }
        let rate = 11_025.0
        let outputSettings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: rate,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 32,
            AVLinearPCMIsFloatKey: true,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsNonInterleaved: false
        ]
        let reader = try AVAssetReader(asset: asset)
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: outputSettings)
        guard reader.canAdd(output) else {
            throw CineoMusicError.invalid("Formato PCM non supportato per questa sorgente.")
        }
        reader.add(output)
        reader.timeRange = CMTimeRange(start: .zero,
                                       duration: CMTime(seconds: seconds, preferredTimescale: 600))
        guard reader.startReading() else {
            throw reader.error ?? CineoMusicError.invalid("Impossibile decodificare l'audio.")
        }
        defer { if reader.status == .reading { reader.cancelReading() } }
        var samples: [Float] = []
        samples.reserveCapacity(Int(rate * min(seconds, 120)))
        while let buffer = output.copyNextSampleBuffer() {
            try Task.checkCancellation()
            defer { CMSampleBufferInvalidate(buffer) }
            guard let block = CMSampleBufferGetDataBuffer(buffer) else { continue }
            let count = CMBlockBufferGetDataLength(block)
            guard count > 0, count % MemoryLayout<Float>.size == 0 else { continue }
            var bytes = Data(count: count)
            let result = bytes.withUnsafeMutableBytes { pointer in
                CMBlockBufferCopyDataBytes(block, atOffset: 0, dataLength: count,
                                           destination: pointer.baseAddress!)
            }
            guard result == noErr else {
                throw CineoMusicError.invalid("Errore di lettura PCM della sorgente.")
            }
            bytes.withUnsafeBytes { pointer in
                for index in stride(from: 0, to: count, by: 4) {
                    let value = pointer.loadUnaligned(fromByteOffset: index, as: Float.self)
                    samples.append(value.isFinite ? value : 0)
                }
            }
            if samples.count >= Int(rate * maxSeconds) { break }
        }
        if reader.status == .failed {
            throw reader.error ?? CineoMusicError.invalid("Decodifica audio interrotta.")
        }
        try Task.checkCancellation()
        return (samples, rate)
    }
}
