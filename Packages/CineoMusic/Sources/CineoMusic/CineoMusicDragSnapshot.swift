import Foundation

public enum CineoMusicDragHandle: Sendable {
    case move, trimStart, trimEnd
}

public struct CineoMusicDragResult: Equatable, Sendable {
    public let offset: Double
    public let clip: CineoMusicClip
}

/// Snapshot-based, deterministic waveform handle editing.
/// Edits are non-destructive and constrained by source/video bounds.
public struct CineoMusicDragSnapshot: Sendable {
    public let offset: Double
    public let clip: CineoMusicClip
    public let sourceDuration: Double
    public let videoDuration: Double
    public let visibleDuration: Double

    public init(offset: Double, clip: CineoMusicClip, sourceDuration: Double,
                videoDuration: Double) {
        self.offset = offset
        self.clip = clip
        self.sourceDuration = sourceDuration
        self.videoDuration = videoDuration
        self.visibleDuration = clip.effectiveDuration(
            sourceDuration: sourceDuration, videoDuration: videoDuration, offset: offset)
    }

    public func edit(handle: CineoMusicDragHandle,
                     deltaSeconds: Double) -> CineoMusicDragResult? {
        guard offset.isFinite, videoDuration.isFinite, videoDuration > 0,
              sourceDuration.isFinite, sourceDuration > 0.04,
              deltaSeconds.isFinite else { return nil }
        var next = clip
        var newOffset = offset
        let minClip = 0.04
        switch handle {
        case .move:
            newOffset = min(max(0, offset + deltaSeconds),
                            max(0, videoDuration - minClip))
        case .trimStart:
            // Move the left edge in both source and video time. Preserve the
            // original right edge; never ripple-edit neighbouring clips.
            let maxDelta = min(visibleDuration - minClip,
                               sourceDuration - clip.sourceIn - minClip,
                               videoDuration - offset - minClip)
            let minDelta = max(-offset, -clip.sourceIn)
            let delta = min(max(deltaSeconds, minDelta), max(minDelta, maxDelta))
            newOffset = offset + delta
            next.sourceIn = clip.sourceIn + delta
            next.duration = visibleDuration - delta
            next.loopCrossfade = min(next.loopCrossfade,
                                      max(0, (sourceDuration - next.sourceIn) / 2))
        case .trimEnd:
            let limit = clip.loop ? videoDuration - offset
                                  : min(videoDuration - offset,
                                        sourceDuration - clip.sourceIn)
            next.duration = min(max(minClip, visibleDuration + deltaSeconds),
                                max(minClip, limit))
        }
        guard (try? next.validate(sourceDuration: sourceDuration,
                                  videoDuration: videoDuration, offset: newOffset)) != nil else {
            return nil
        }
        return CineoMusicDragResult(offset: newOffset, clip: next)
    }

    public func selectedHandle(touchX: Double, timelineWidth: Double,
                               handleThreshold: Double = 10) -> CineoMusicDragHandle {
        guard timelineWidth > 0, videoDuration > 0 else { return .move }
        let start = offset / videoDuration * timelineWidth
        let end = (offset + visibleDuration) / videoDuration * timelineWidth
        if abs(touchX - start) <= handleThreshold { return .trimStart }
        if abs(touchX - end) <= handleThreshold { return .trimEnd }
        return .move
    }
}
