import Foundation

/// Non-destructive clip edit; the ACE-Step generation recipe is unchanged.
/// A loop repeats from sourceIn to the end of the source, without time-stretch.
public struct CineoMusicClip: Codable, Equatable, Sendable {
    public var sourceIn: Double
    public var duration: Double?
    public var loop: Bool
    /// Overlap between successive repeats, in seconds. 0 retains legacy hard looping.
    public var loopCrossfade: Double

    public init(sourceIn: Double = 0, duration: Double? = nil, loop: Bool = false,
                loopCrossfade: Double = 0) {
        self.sourceIn = sourceIn
        self.duration = duration
        self.loop = loop
        self.loopCrossfade = loopCrossfade
    }

    private enum CodingKeys: String, CodingKey {
        case sourceIn, duration, loop, loopCrossfade
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        sourceIn = try c.decodeIfPresent(Double.self, forKey: .sourceIn) ?? 0
        duration = try c.decodeIfPresent(Double.self, forKey: .duration)
        loop = try c.decodeIfPresent(Bool.self, forKey: .loop) ?? false
        loopCrossfade = try c.decodeIfPresent(Double.self, forKey: .loopCrossfade) ?? 0
    }

    public func validate(sourceDuration: Double, videoDuration: Double, offset: Double) throws {
        guard sourceDuration.isFinite, sourceDuration > 0.04,
              videoDuration.isFinite, videoDuration > 0,
              offset.isFinite, offset >= 0, offset < videoDuration,
              sourceIn.isFinite, sourceIn >= 0, sourceIn < sourceDuration - 0.02,
              duration == nil || (duration!.isFinite && duration! >= 0.04),
              loopCrossfade.isFinite, loopCrossfade >= 0,
              loopCrossfade <= 2,
              loopCrossfade <= (sourceDuration - sourceIn) / 2
        else { throw CineoMusicError.invalid("Taglio/loop musicale: durata, origine o crossfade non validi.") }
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
        let cycle = sourceDuration - sourceIn
        let overlap = loop ? loopCrossfade : 0
        let strideSeconds = cycle - overlap
        var elapsed = 0.0
        var segments: [CineoMusicSegment] = []
        while elapsed < total - 0.000001 {
            guard segments.count < 4096 else {
                throw CineoMusicError.invalid("Loop musicale troppo breve: supera 4096 ripetizioni.")
            }
            let part = min(cycle, total - elapsed)
            guard part > 0.000001 else { break }
            segments.append(CineoMusicSegment(sourceStart: sourceIn,
                                               timelineStart: offset + elapsed,
                                               duration: part))
            if !loop { break }
            elapsed += strideSeconds
        }
        return segments
    }

    /// The source and gains of all audible loop layers at output-time t.
    /// In crossfade there are at most two sources, with linear equal-gain
    /// transitions; this contract is shared by AVPlayers and AVAudioMix.
    public func previewLayers(videoTime: Double, sourceDuration: Double,
                              videoDuration: Double, offset: Double) -> [CineoMusicLayer] {
        let local = videoTime - offset
        let total = effectiveDuration(sourceDuration: sourceDuration,
                                       videoDuration: videoDuration, offset: offset)
        let cycle = sourceDuration - sourceIn
        guard local >= 0, local < total, cycle > 0 else { return [] }
        guard loop else {
            return [.init(repeatIndex: 0, sourcePosition: sourceIn + local, gain: 1)]
        }
        let overlap = loopCrossfade
        let strideSeconds = cycle - overlap
        guard strideSeconds > 0 else { return [] }
        let currentIndex = Int(floor(local / strideSeconds))
        var layers: [CineoMusicLayer] = []
        for i in max(0, currentIndex - 1)...currentIndex {
            let relative = local - Double(i) * strideSeconds
            guard relative >= 0, relative < cycle else { continue }
            let entering = i > 0 && overlap > 0 ? min(1, relative / overlap) : 1
            let leaving = overlap > 0 && Double(i + 1) * strideSeconds < total
                ? min(1, (cycle - relative) / overlap) : 1
            let gain = max(0, min(entering, leaving))
            if gain > 0.00001 {
                layers.append(.init(repeatIndex: i,
                                    sourcePosition: sourceIn + relative, gain: gain))
            }
        }
        return layers
    }

    /// Compatibility convenience for callers needing a single source clock.
    public func playbackPosition(videoTime: Double, sourceDuration: Double,
                                 videoDuration: Double, offset: Double) -> Double? {
        previewLayers(videoTime: videoTime, sourceDuration: sourceDuration,
                      videoDuration: videoDuration, offset: offset)
            .max(by: { $0.gain < $1.gain })?.sourcePosition
    }
}

public struct CineoMusicLayer: Equatable, Sendable {
    public let repeatIndex: Int
    public let sourcePosition: Double
    public let gain: Double
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
