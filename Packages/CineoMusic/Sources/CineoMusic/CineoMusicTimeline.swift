import Foundation

/// Non-destructive clip edit; the ACE-Step generation recipe is unchanged.
/// A loop repeats from sourceIn to the end of the source, without time-stretch.
public struct CineoMusicClip: Codable, Equatable, Sendable {
    public var sourceIn: Double
    public var duration: Double?
    public var loop: Bool

    public init(sourceIn: Double = 0, duration: Double? = nil, loop: Bool = false) {
        self.sourceIn = sourceIn
        self.duration = duration
        self.loop = loop
    }

    public func validate(sourceDuration: Double, videoDuration: Double, offset: Double) throws {
        guard sourceDuration.isFinite, sourceDuration > 0.04,
              videoDuration.isFinite, videoDuration > 0,
              offset.isFinite, offset >= 0, offset < videoDuration,
              sourceIn.isFinite, sourceIn >= 0, sourceIn < sourceDuration - 0.02,
              duration == nil || (duration!.isFinite && duration! >= 0.04)
        else { throw CineoMusicError.invalid("Taglio musicale: durata, posizione o sorgente non valida.") }
    }

    public func effectiveDuration(sourceDuration: Double, videoDuration: Double, offset: Double) -> Double {
        let availableVideo = max(0, videoDuration - offset)
        let remainingSource = max(0, sourceDuration - sourceIn)
        let requested = duration ?? (loop ? availableVideo : remainingSource)
        return max(0, min(availableVideo, requested, loop ? availableVideo : remainingSource))
    }

    public func segments(sourceDuration: Double, videoDuration: Double,
                         offset: Double) throws -> [CineoMusicSegment] {
        try validate(sourceDuration: sourceDuration, videoDuration: videoDuration, offset: offset)
        let total = effectiveDuration(sourceDuration: sourceDuration, videoDuration: videoDuration, offset: offset)
        guard total >= 0.04 else { return [] }
        let sourceLoop = sourceDuration - sourceIn
        var elapsed = 0.0
        var segments: [CineoMusicSegment] = []
        while elapsed < total - 0.000001 {
            guard segments.count < 4096 else {
                throw CineoMusicError.invalid("Loop musicale troppo breve: supera 4096 ripetizioni.")
            }
            let part = min(sourceLoop, total - elapsed)
            guard part > 0.000001 else { break }
            segments.append(CineoMusicSegment(sourceStart: sourceIn, timelineStart: offset + elapsed,
                                               duration: part))
            elapsed += part
            if !loop { break }
        }
        return segments
    }

    /// Video-clock -> source clock, returned only while this edit is audible.
    public func playbackPosition(videoTime: Double, sourceDuration: Double,
                                 videoDuration: Double, offset: Double) -> Double? {
        let local = videoTime - offset
        let length = effectiveDuration(sourceDuration: sourceDuration, videoDuration: videoDuration, offset: offset)
        guard local >= 0, local < length, sourceDuration > sourceIn else { return nil }
        let cycle = sourceDuration - sourceIn
        return sourceIn + (loop ? local.truncatingRemainder(dividingBy: cycle) : local)
    }
}

public struct CineoMusicSegment: Equatable, Sendable {
    public let sourceStart: Double
    public let timelineStart: Double
    public let duration: Double
}

/// A proposed, explicitly confirmable edit. Never mutates camera state.
public struct CineoBeatAlignment: Equatable, Sendable {
    public let keyframeIndex: Int
    public let from: Double
    public let to: Double
    public var delta: Double { to - from }

    public init(keyframeIndex: Int, from: Double, to: Double) {
        self.keyframeIndex = keyframeIndex
        self.from = from
        self.to = to
    }
}

public struct CineoBeatKeyframe: Equatable, Sendable {
    public let time: Double
    public let zoom: Double
    public init(time: Double, zoom: Double) {
        self.time = time
        self.zoom = zoom
    }
}

/// Chooses actual detected musical transients near a camera focus peak.
/// BPM alone is not treated as measured beat timing.
public enum CineoBeatSync {
    public static func propose(keyframes: [CineoBeatKeyframe], playhead: Double,
                               onsetSeconds: [Double], clip: CineoMusicClip,
                               sourceDuration: Double, videoDuration: Double,
                               offset: Double, maxShift: Double = 0.35) -> CineoBeatAlignment? {
        guard keyframes.count > 0, maxShift > 0, maxShift.isFinite, playhead.isFinite else { return nil }
        let indexed = keyframes.indices.filter { i in
            keyframes[i].zoom > 1.02 &&
            abs(keyframes[i].time - playhead) <= 0.75 &&
            (i == 0 || keyframes[i].zoom > keyframes[i - 1].zoom + 0.015)
        }
        guard let i = indexed.min(by: {
            abs(keyframes[$0].time - playhead) < abs(keyframes[$1].time - playhead)
        }) else { return nil }
        let original = keyframes[i].time
        let playable = clip.effectiveDuration(sourceDuration: sourceDuration,
                                               videoDuration: videoDuration, offset: offset)
        guard playable > 0, sourceDuration > clip.sourceIn else { return nil }
        let cycle = sourceDuration - clip.sourceIn
        var best: Double?
        for onset in onsetSeconds where onset.isFinite && onset >= clip.sourceIn && onset < sourceDuration {
            let withinCycle = onset - clip.sourceIn
            if clip.loop {
                var k = 0
                while Double(k) * cycle + withinCycle < playable {
                    let candidate = offset + Double(k) * cycle + withinCycle
                    if abs(candidate - original) <= maxShift &&
                       (best == nil || abs(candidate - original) < abs(best! - original)) {
                        best = candidate
                    }
                    k += 1
                    if k > 4096 { break }
                }
            } else {
                let candidate = offset + withinCycle
                if candidate < offset + playable, abs(candidate - original) <= maxShift &&
                    (best == nil || abs(candidate - original) < abs(best! - original)) {
                    best = candidate
                }
            }
        }
        guard let target = best, abs(target - original) > 0.005,
              target >= 0, target < videoDuration,
              (i == 0 || target > keyframes[i - 1].time + 0.06),
              (i + 1 == keyframes.count || target < keyframes[i + 1].time - 0.06)
        else { return nil }
        return CineoBeatAlignment(keyframeIndex: i, from: original, to: target)
    }
}
