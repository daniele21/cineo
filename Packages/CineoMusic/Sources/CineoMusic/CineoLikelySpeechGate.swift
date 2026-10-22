import Foundation

/// Combine the OS built-in sound classifier's coarse likely-speech windows
/// with fine (20ms) local RMS activity. Silence is never treated as speech.
/// This is probabilistic sound classification, not transcription or VAD
/// ground truth. The model's confidence threshold is enforced at the caller.
public enum CineoLikelySpeechGate {
    public static func intersection(activity: [CineoAudioActivityRange],
                                    speechWindows: [CineoAudioActivityRange],
                                    edgeTolerance: Double = 0.1) -> [CineoAudioActivityRange] {
        guard edgeTolerance.isFinite, edgeTolerance >= 0 else { return [] }
        var result: [CineoAudioActivityRange] = []
        for act in activity {
            guard act.start.isFinite, act.end.isFinite, act.end > act.start else { continue }
            for likely in speechWindows where likely.start.isFinite && likely.end.isFinite
                && likely.end > likely.start {
                let a = max(act.start, likely.start - edgeTolerance)
                let b = min(act.end, likely.end + edgeTolerance)
                if b > a { result.append(.init(start: a, end: b)) }
            }
        }
        let ordered = result.sorted { $0.start < $1.start }
        var merged: [CineoAudioActivityRange] = []
        for next in ordered {
            if let last = merged.last, next.start <= last.end + 0.06 {
                merged[merged.count - 1] = .init(start: last.start, end: max(last.end, next.end))
            } else { merged.append(next) }
        }
        return merged
    }
}
