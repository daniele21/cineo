import Foundation

/// Data is source-relative; music offset, source trim and looping are applied
/// only by the timeline. These are onset *candidates*, not BPM ground truth.
public struct CineoBeatAnalysis: Equatable, Sendable {
    public let sourceDuration: Double
    /// Positive linear envelopes, evenly spaced over the source duration.
    public let waveform: [Float]
    public let onsets: [Double]
    public let estimatedBPM: Double?
    /// 20ms resolution RMS envelopes for audio-activity ducking. Unlike the
    /// 256-column waveform, this retains short pauses and speech boundaries.
    public let activityLevels: [Float]

    public init(sourceDuration: Double, waveform: [Float], onsets: [Double],
                estimatedBPM: Double?, activityLevels: [Float] = []) {
        self.sourceDuration = sourceDuration
        self.waveform = waveform
        self.onsets = onsets
        self.estimatedBPM = estimatedBPM
        self.activityLevels = activityLevels
    }
}

/// Streaming-friendly deterministic energy/attack novelty detector.
/// No cloud, LLM, or AI model. Short-time high-frequency changes are weighted
/// to expose drum transients rather than turning provided BPM into fake beats.
public enum CineoBeatAnalyzer {
    public static func analyze(samples: [Float], sampleRate: Double,
                               waveformBins: Int = 256) -> CineoBeatAnalysis {
        guard sampleRate.isFinite, sampleRate > 100, !samples.isEmpty else {
            return .init(sourceDuration: 0, waveform: [], onsets: [], estimatedBPM: nil)
        }
        let count = samples.count
        let duration = Double(count) / sampleRate
        let bins = min(1024, max(16, waveformBins))
        var waveform = [Float](repeating: 0, count: bins)
        for i in 0..<count {
            let value = samples[i].isFinite ? min(1, abs(samples[i])) : 0
            waveform[min(bins - 1, i * bins / count)] = max(waveform[min(bins - 1, i * bins / count)], value)
        }

        let hop = max(16, Int(sampleRate * 0.02))
        let window = max(hop * 2, Int(sampleRate * 0.04))
        guard count > window * 2 else {
            return .init(sourceDuration: duration, waveform: waveform, onsets: [], estimatedBPM: nil)
        }
        let frames = 1 + (count - window) / hop
        var levels = [Double](repeating: 0, count: frames)
        var attacks = [Double](repeating: 0, count: frames)
        for frame in 0..<frames {
            let start = frame * hop
            var square = 0.0
            var changes = 0.0
            var previous = Double(samples[start].isFinite ? samples[start] : 0)
            for j in start..<(start + window) {
                let x = Double(samples[j].isFinite ? samples[j] : 0)
                square += x * x
                changes += abs(x - previous)
                previous = x
            }
            levels[frame] = sqrt(square / Double(window))
            attacks[frame] = changes / Double(window)
        }

        var novelty = [Double](repeating: 0, count: frames)
        for i in 1..<frames {
            // Both energy onset and changes in high-frequency content.
            novelty[i] = max(0, levels[i] - levels[i - 1]) +
                         0.2 * max(0, attacks[i] - attacks[i - 1])
        }
        // Adaptive moving mean over a 0.7s window. Quiet intros should not
        // erase strong later hits, nor should a lone noise click create BPM.
        let radius = max(2, Int(sampleRate * 0.35 / Double(hop)))
        var prefix = [Double](repeating: 0, count: frames + 1)
        for i in 0..<frames { prefix[i + 1] = prefix[i] + novelty[i] }
        let loudness = levels.reduce(0, +) / Double(frames)
        let thresholdFloor = max(0.0005, loudness * 0.015)
        let minSeparation = max(1, Int(0.16 * sampleRate / Double(hop)))
        var candidates: [(Double, Double)] = []
        var lastIndex = -minSeparation
        for i in 1..<(frames - 1) {
            let lo = max(0, i - radius)
            let hi = min(frames, i + radius + 1)
            let localMean = (prefix[hi] - prefix[lo]) / Double(hi - lo)
            let threshold = max(thresholdFloor, localMean * 1.55)
            let value = novelty[i]
            guard value > threshold, value >= novelty[i - 1],
                  value > novelty[i + 1], levels[i] > thresholdFloor else { continue }
            let t = Double(i * hop) / sampleRate
            if i - lastIndex < minSeparation {
                if let last = candidates.last, value > last.1 {
                    candidates[candidates.count - 1] = (t, value)
                    lastIndex = i
                }
            } else {
                candidates.append((t, value))
                lastIndex = i
            }
        }

        let onsets = candidates.map { $0.0 }
        // Only infer BPM if multiple recurring intervals agree; otherwise nil.
        let intervals = zip(onsets, onsets.dropFirst()).map { $0.1 - $0.0 }
            .filter { $0 >= 0.25 && $0 <= 1.5 }.sorted()
        var bpm: Double?
        if intervals.count >= 5 {
            let median = intervals[intervals.count / 2]
            let agreement = Double(intervals.filter { abs($0 - median) < 0.07 }.count) /
                            Double(intervals.count)
            if agreement >= 0.6 { bpm = (60 / median * 10).rounded() / 10 }
        }
        return .init(sourceDuration: duration, waveform: waveform, onsets: onsets,
                     estimatedBPM: bpm, activityLevels: levels.map { Float($0) })
    }
}
