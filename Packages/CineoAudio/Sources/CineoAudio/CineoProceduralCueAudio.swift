import Foundation
import CineoMusic

/// Small deterministic PCM effects for Cineo's edit cues. Waveform generation
/// is platform-independent and requires no model, network or copyrighted asset.
public enum CineoProceduralCueAudio {
    public static let sampleRate = 48_000

    public static func wav(event: CineoCueSoundEvent) -> Data {
        let count = max(1, Int((event.duration * Double(sampleRate)).rounded()))
        var audio = Data(capacity: count * 2)
        let twoPi = 2 * Double.pi
        var rng: UInt32 = 0xD1CE_0001
        for index in 0..<count {
            let t = Double(index) / Double(sampleRate)
            let phase = t / event.duration
            rng = rng &* 1_664_525 &+ 1_013_904_223
            let noise = Double(Int(rng >> 16) - 32768) / 32768.0
            let wave: Double
            switch event.kind {
            case .hit:
                let envelope = exp(-18 * t) * min(1, t / 0.002)
                wave = envelope * (0.8 * sin(twoPi * (160 * t - 120 * t * t)) + noise * 0.1)
            case .crescendo:
                let ramp = pow(max(0, phase), 1.6) * min(1, (1 - phase) / 0.045)
                wave = ramp * (0.35 * sin(twoPi * (350 * t + 900 * t * t)) + 0.15 * noise)
            case .transition:
                let envelope = sin(Double.pi * min(1, max(0, phase)))
                wave = envelope * (0.3 * sin(twoPi * (650 * t - 300 * t * t)) + 0.23 * noise)
            }
            let sample = Int16((min(1, max(-1, wave * 0.65)) * 32767).rounded())
            var v = sample.littleEndian
            withUnsafeBytes(of: &v) { audio.append(contentsOf: $0) }
        }

        var wav = Data(capacity: 44 + audio.count)
        func append(_ bytes: String) { wav.append(contentsOf: bytes.utf8) }
        func integer<T: FixedWidthInteger>(_ value: T) {
            var little = value.littleEndian
            withUnsafeBytes(of: &little) { wav.append(contentsOf: $0) }
        }
        append("RIFF")
        integer(UInt32(36 + audio.count))
        append("WAVEfmt ")
        integer(UInt32(16))
        integer(UInt16(1))
        integer(UInt16(1))
        integer(UInt32(sampleRate))
        integer(UInt32(sampleRate * 2))
        integer(UInt16(2))
        integer(UInt16(16))
        append("data")
        integer(UInt32(audio.count))
        wav.append(audio)
        return wav
    }
}
