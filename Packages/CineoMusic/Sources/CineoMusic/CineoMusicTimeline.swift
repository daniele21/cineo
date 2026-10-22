import Foundation

/// Non-destructive clip edit; the ACE-Step generation recipe is unchanged.
/// A loop repeats from sourceIn to the end of the source, without time-stretch.
public struct CineoMusicClip: Codable, Equatable, Sendable {
    public var sourceIn: Double
    public var duration: Double?
    public var loop: Bool
    /// Optional for backward compatibility with older music.json project files.
    public var crossfade: Double?

    public init(sourceIn: Double = 0, duration: Double? = nil, loop: Bool = false,
                crossfade: Double? = nil) {
        self.sourceIn = sourceIn
        self.duration = duration
        self.loop = loop
        self.crossfade = crossfade
    }

    public func validate(sourceDuration: Double, videoDuration: Double, offset: Double) throws {
        guard sourceDuration.isFinite, sourceDuration > 0.04,
              videoDuration.isFinite, videoDuration > 0,
              offset.isFinite, offset >= 0, offset < videoDuration,
              sourceIn.isFinite, sourceIn >= 0, sourceIn < sourceDuration - 0.02,
              duration == nil || (duration!.isFinite && duration! >= 0.04),
              crossfade == nil || (crossfade!.isFinite && crossfade! >= 0 &&
                                    crossfade! <= 1.5 && crossfade! < (sourceDuration - sourceIn) * 0.45)
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

    /// Non-destructive arrangement with optional overlapping two-lane loops.
    /// When crossfade=0, this is equivalent to segments() with no overlaps.
    public func arrangedSegments(sourceDuration: Double, videoDuration: Double,
                                 offset: Double) throws -> [CineoMusicArrangedSegment] {
        try validate(sourceDuration: sourceDuration, videoDuration: videoDuration, offset: offset)
        let total = effectiveDuration(sourceDuration: sourceDuration,
                                      videoDuration: videoDuration, offset: offset)
        guard total >= 0.04 else { return [] }
        let span = sourceDuration - sourceIn
        let fade = loop ? (crossfade ?? 0) : 0
        let step = span - fade
        var arranged: [CineoMusicArrangedSegment] = []
        var relativeStart = 0.0
        while relativeStart < total - 0.000001 {
            guard arranged.count < 4096 else {
                throw CineoMusicError.invalid("Troppi cicli musicali: massimo 4096.")
            }
            let length = min(span, total - relativeStart)
            let nextStart = relativeStart + step
            let actualFadeOut = loop && fade > 0 && nextStart < relativeStart + length - 0.000001
                ? (relativeStart + length - nextStart) : 0
            let fadeIn = arranged.isEmpty ? 0 : min(fade, length)
            arranged.append(.init(sourceStart: sourceIn, timelineStart: offset + relativeStart,
                                  duration: length, lane: arranged.count % 2,
                                  fadeIn: fadeIn, fadeOut: actualFadeOut))
            if !loop { break }
            relativeStart += step
        }
        return arranged
    }

    /// At most two active source positions when adjacent loop cycles overlap.
    /// Each lane carries its own linear gain, for exact AVPlayer/AVAudioMix reuse.
    public func sources(at videoTime: Double, sourceDuration: Double,
                        videoDuration: Double, offset: Double) -> [CineoMusicPlaybackSource] {
        guard let segments = try? arrangedSegments(sourceDuration: sourceDuration,
                                                   videoDuration: videoDuration, offset: offset) else {
            return []
        }
        return segments.compactMap { part in
            let elapsed = videoTime - part.timelineStart
            guard elapsed >= 0 && elapsed < part.duration else { return nil }
            let gainIn = part.fadeIn > 0 ? min(1, elapsed / part.fadeIn) : 1
            let gainOut = part.fadeOut > 0 ?
                min(1, (part.duration - elapsed) / part.fadeOut) : 1
            return CineoMusicPlaybackSource(lane: part.lane,
                sourceTime: part.sourceStart + elapsed,
                gain: max(0, min(1, gainIn * gainOut)))
        }
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

public struct CineoMusicArrangedSegment: Equatable, Sendable {
    public let sourceStart: Double
    public let timelineStart: Double
    public let duration: Double
    public let lane: Int
    public let fadeIn: Double
    public let fadeOut: Double
}

public struct CineoMusicPlaybackSource: Equatable, Sendable {
    public let lane: Int
    public let sourceTime: Double
    public let gain: Double
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
    /// Explicit manual cue alignment; no rhythm detection is required.
    /// Returns a proposal only if a selected zoom peak remains ordered.
    public static func proposeToTime(keyframes: [CineoBeatKeyframe],
                                     playhead: Double, targetTime: Double,
                                     maxShift: Double = 0.60) -> CineoBeatAlignment? {
        guard playhead.isFinite, targetTime.isFinite, maxShift.isFinite,
              maxShift > 0 else { return nil }
        let candidates = keyframes.indices.filter { i in
            keyframes[i].zoom > 1.02 &&
            abs(keyframes[i].time - playhead) <= 0.75 &&
            (i == 0 || keyframes[i].zoom > keyframes[i - 1].zoom + 0.015)
        }
        guard let i = candidates.min(by: {
            abs(keyframes[$0].time - playhead) < abs(keyframes[$1].time - playhead)
        }), abs(targetTime - keyframes[i].time) <= maxShift,
            abs(targetTime - keyframes[i].time) > 0.005,
            targetTime >= 0,
            (i == 0 || targetTime > keyframes[i - 1].time + 0.06),
            (i + 1 == keyframes.count || targetTime < keyframes[i + 1].time - 0.06)
        else { return nil }
        return CineoBeatAlignment(keyframeIndex: i,
                                  from: keyframes[i].time, to: targetTime)
    }

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
        guard let segments = try? clip.arrangedSegments(sourceDuration: sourceDuration,
                                                         videoDuration: videoDuration,
                                                         offset: offset) else { return nil }
        var best: Double?
        for part in segments {
            for onset in onsetSeconds where onset.isFinite &&
                    onset >= part.sourceStart &&
                    onset < part.sourceStart + part.duration {
                let candidate = part.timelineStart + onset - part.sourceStart
                if abs(candidate - original) <= maxShift &&
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
