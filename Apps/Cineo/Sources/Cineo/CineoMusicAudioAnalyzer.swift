import Foundation
import AVFoundation
import CineoMusic

/// Decode at 11.025 kHz / mono / float32 for waveform and transient analysis.
/// AVFoundation does the decoding; no FFmpeg, Python or model download.
enum CineoMusicAudioAnalyzer {
    static func analyze(url: URL) async throws -> CineoBeatAnalysis {
        let asset = AVURLAsset(url: url)
        guard let track = try await asset.loadTracks(withMediaType: .audio).first else {
            throw CineoMusicError.invalid("La sorgente non contiene una traccia audio.")
        }
        let maxSeconds = min(600, max(0, (try await asset.load(.duration)).seconds))
        guard maxSeconds > 0 else {
            throw CineoMusicError.invalid("Durata musicale non disponibile.")
        }
        let reader = try AVAssetReader(asset: asset)
        let rate = 11_025.0
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: rate,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 32,
            AVLinearPCMIsFloatKey: true,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsNonInterleaved: false
        ]
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: settings)
        reader.add(output)
        reader.timeRange = CMTimeRange(start: .zero,
                                       duration: CMTime(seconds: maxSeconds, preferredTimescale: 600))
        guard reader.startReading() else {
            throw reader.error ?? CineoMusicError.invalid("Impossibile decodificare la traccia musicale.")
        }
        defer { if reader.status == .reading { reader.cancelReading() } }
        var samples: [Float] = []
        samples.reserveCapacity(Int(rate * min(maxSeconds, 120)))
        while let buffer = output.copyNextSampleBuffer() {
            try Task.checkCancellation()
            defer { CMSampleBufferInvalidate(buffer) }
            guard let block = CMSampleBufferGetDataBuffer(buffer) else { continue }
            let count = CMBlockBufferGetDataLength(block)
            guard count > 0, count % MemoryLayout<Float>.size == 0 else { continue }
            var bytes = Data(count: count)
            let code = bytes.withUnsafeMutableBytes { ptr in
                CMBlockBufferCopyDataBytes(block, atOffset: 0, dataLength: count,
                                           destination: ptr.baseAddress!)
            }
            guard code == noErr else {
                throw CineoMusicError.invalid("Errore durante la lettura PCM della musica.")
            }
            bytes.withUnsafeBytes { ptr in
                for index in stride(from: 0, to: count, by: 4) {
                    let sample = ptr.loadUnaligned(fromByteOffset: index, as: Float.self)
                    samples.append(sample.isFinite ? sample : 0)
                }
            }
            if samples.count >= Int(rate * 600) { break }
        }
        if reader.status == .failed {
            throw reader.error ?? CineoMusicError.invalid("Decodifica audio interrotta.")
        }
        try Task.checkCancellation()
        return CineoBeatAnalyzer.analyze(samples: samples, sampleRate: rate)
    }
}
