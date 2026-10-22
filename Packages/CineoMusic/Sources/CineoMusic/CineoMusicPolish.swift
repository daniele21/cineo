import Foundation

/// Music-volume automation while the recording's original audio is active.
/// This is an amplitude gate, not speaker/voice identification.
public struct CineoDuckingSettings: Codable, Equatable, Sendable {
    public var enabled: Bool
    public var level: Double
    public var threshold: Double
    public var attack: Double
    public var release: Double

    public init(enabled: Bool = false, level: Double = 0.25, threshold: Double = 0.08,
                attack: Double = 0.20, release: Double = 0.55) {
        self.enabled = enabled
        self.level = level
        self.threshold = threshold
        self.attack = attack
        self.release = release
    }

    public func validate() throws {
        guard level.isFinite, (0...1).contains(level),
              threshold.isFinite, (0.01...1).contains(threshold),
              attack.isFinite, (0...2).contains(attack),
              release.isFinite, (0...3).contains(release) else {
            throw CineoMusicError.invalid("Ducking: valori volume, soglia o tempi non validi.")
        }
    }

    public func gain(at time: Double, activeRanges: [CineoAudioActivityRange]) -> Double {
        guard enabled, time.isFinite else { return 1 }
        var strength = 0.0
        for range in activeRanges {
            let attackStart = range.start - attack
            let releaseEnd = range.end + release
            if time < attackStart || time > releaseEnd { continue }
            if time < range.start {
                strength = max(strength, attack > 0 ? (time - attackStart) / attack : 0)
            } else if time <= range.end {
                strength = 1
            } else {
                strength = max(strength, release > 0 ? 1 - (time - range.end) / release : 0)
            }
        }
        return max(0, min(1, 1 - (1 - level) * strength))
    }

    /// Piecewise linear volume points, including arrival/release ramps.
    /// Reuses the same gain(at:) contract as live preview.
    public func envelopePoints(activeRanges: [CineoAudioActivityRange],
                               clipStart: Double, clipEnd: Double) -> [CineoMusicGainPoint] {
        guard clipEnd > clipStart else { return [] }
        var times: [Double] = [clipStart, clipEnd]
        if enabled {
            for range in activeRanges {
                times.append(contentsOf: [range.start - attack, range.start,
                                          range.end, range.end + release])
            }
        }
        let ordered = Array(Set(times.filter { $0.isFinite && $0 >= clipStart && $0 <= clipEnd }))
            .sorted()
        return ordered.map { CineoMusicGainPoint(time: $0,
                                                 gain: gain(at: $0, activeRanges: activeRanges)) }
    }
}

public struct CineoAudioActivityRange: Codable, Equatable, Sendable {
    public let start: Double
    public let end: Double
    public init(start: Double, end: Double) {
        self.start = start
        self.end = end
    }
}

public struct CineoMusicGainPoint: Equatable, Sendable {
    public let time: Double
    public let gain: Double
}

/// Conservative heuristic; 256 waveform buckets => coarse resolution.
/// Labels must always refer to "audio activity", never verified narration.
/// Tiny isolated clicks are ignored; close activity windows are merged.
public enum CineoAudioActivityDetector {
    public static func ranges(peakBins: [Float], duration: Double,
                              threshold: Double, minimumActiveSeconds: Double = 0.25,
                              joinGapSeconds: Double = 0.35) -> [CineoAudioActivityRange] {
        guard duration.isFinite, duration > 0, !peakBins.isEmpty,
              threshold.isFinite, threshold > 0 else { return [] }
        let binLength = duration / Double(peakBins.count)
        var groups: [CineoAudioActivityRange] = []
        var openStart: Double?
        var lastEnd = 0.0
        for (index, value) in peakBins.enumerated() {
            let level = value.isFinite ? abs(value) : 0
            if Double(level) >= threshold {
                let start = Double(index) * binLength
                if openStart == nil { openStart = start }
                lastEnd = min(duration, Double(index + 1) * binLength)
            } else if let start = openStart {
                if lastEnd - start >= minimumActiveSeconds {
                    groups.append(CineoAudioActivityRange(start: start, end: lastEnd))
                }
                openStart = nil
            }
        }
        if let start = openStart, lastEnd - start >= minimumActiveSeconds {
            groups.append(CineoAudioActivityRange(start: start, end: lastEnd))
        }
        var merged: [CineoAudioActivityRange] = []
        for group in groups {
            if let last = merged.last, group.start - last.end <= joinGapSeconds {
                merged[merged.count - 1] = CineoAudioActivityRange(start: last.start, end: group.end)
            } else { merged.append(group) }
        }
        return Array(merged.prefix(1024))
    }
}

public enum CineoMusicCueKind: String, Codable, CaseIterable, Sendable {
    case hit, crescendo, transition
}

public struct CineoMusicCue: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var at: Double
    public var kind: CineoMusicCueKind
    public var label: String

    public init(id: String = UUID().uuidString, at: Double, kind: CineoMusicCueKind,
                label: String = "") {
        self.id = id
        self.at = at
        self.kind = kind
        self.label = label
    }

    public func validate(videoDuration: Double) throws {
        guard !id.isEmpty, id.count < 100,
              at.isFinite, at >= 0, at < videoDuration,
              label.utf8.count <= 80 else {
            throw CineoMusicError.invalid("Cue musicale non valido.")
        }
    }
}
