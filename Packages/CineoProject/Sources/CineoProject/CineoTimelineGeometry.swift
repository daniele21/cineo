import Foundation

/// Time projection for the native editor. Snapping is measured in view pixels,
/// not fixed milliseconds, so it behaves consistently at every zoom level.
public struct CineoTimelineViewport: Equatable, Sendable {
    public let startSeconds: Double
    public let endSeconds: Double
    public let widthPixels: Double

    public init(startSeconds: Double, endSeconds: Double, widthPixels: Double) throws {
        guard [startSeconds, endSeconds, widthPixels].allSatisfy(\.isFinite),
              startSeconds >= 0, endSeconds > startSeconds, widthPixels > 0
        else { throw CineoTimelineError.invalidViewport }
        self.startSeconds = startSeconds
        self.endSeconds = endSeconds
        self.widthPixels = widthPixels
    }

    public func time(atPixel x: Double) -> Double {
        guard x.isFinite else { return startSeconds }
        let t = min(1, max(0, x / widthPixels))
        return startSeconds + t * (endSeconds - startSeconds)
    }

    public func pixel(atTime time: Double) -> Double {
        guard time.isFinite else { return 0 }
        return min(widthPixels, max(0, (time - startSeconds) /
                                    (endSeconds - startSeconds) * widthPixels))
    }

    /// Selects nearest anchor; ties resolve to the earliest anchor.
    public func snappedTime(_ time: Double, anchors: [Double],
                            thresholdPixels: Double = 8) -> Double {
        guard time.isFinite, thresholdPixels.isFinite, thresholdPixels >= 0
        else { return time }
        let clampedTime = self.time(atPixel: pixel(atTime: time))
        var bestTime = clampedTime
        var bestDistance = thresholdPixels
        var hasAnchor = false
        for anchor in anchors where anchor.isFinite && anchor >= startSeconds && anchor <= endSeconds {
            let distance = abs(pixel(atTime: anchor) - pixel(atTime: clampedTime))
            if distance < bestDistance || (!hasAnchor && distance <= bestDistance) ||
                (hasAnchor && distance == bestDistance && anchor < bestTime) {
                bestTime = anchor
                bestDistance = distance
                hasAnchor = true
            }
        }
        return bestTime
    }
}

public enum CineoTimelineError: Error, Equatable, Sendable {
    case invalidViewport
    case invalidRegion
}

/// A generic editable output-time timeline region; the media source is never changed.
public struct CineoTimelineRegion: Equatable, Codable, Sendable {
    public let id: String
    public let startSeconds: Double
    public let endSeconds: Double

    public init(id: String, startSeconds: Double, endSeconds: Double) throws {
        guard !id.isEmpty, startSeconds.isFinite, endSeconds.isFinite,
              startSeconds >= 0, endSeconds > startSeconds
        else { throw CineoTimelineError.invalidRegion }
        self.id = id
        self.startSeconds = startSeconds
        self.endSeconds = endSeconds
    }

    public var duration: Double { endSeconds - startSeconds }
}

public enum CineoTimelineRegionEdit: Sendable {
    case move(startSeconds: Double)
    case resizeStart(seconds: Double)
    case resizeEnd(seconds: Double)
}

public enum CineoTimelineEditEngine {
    /// Rejects overlaps rather than silently moving a region away from the cursor.
    /// Caller records the returned value in its undoable transaction.
    public static func applying(
        _ edit: CineoTimelineRegionEdit, to region: CineoTimelineRegion,
        duration: Double, minimumDuration: Double = 0.1,
        siblings: [CineoTimelineRegion] = []
    ) -> CineoTimelineRegion? {
        guard duration.isFinite, duration > 0, minimumDuration.isFinite,
              minimumDuration > 0, region.endSeconds <= duration,
              siblings.allSatisfy({ $0.endSeconds <= duration })
        else { return nil }

        let start: Double
        let end: Double
        switch edit {
        case .move(let proposedStart):
            guard proposedStart.isFinite else { return nil }
            start = max(0, min(proposedStart, duration - region.duration))
            end = start + region.duration
        case .resizeStart(let proposedStart):
            guard proposedStart.isFinite else { return nil }
            start = max(0, min(proposedStart, region.endSeconds - minimumDuration))
            end = region.endSeconds
        case .resizeEnd(let proposedEnd):
            guard proposedEnd.isFinite else { return nil }
            start = region.startSeconds
            end = min(duration, max(proposedEnd, start + minimumDuration))
        }
        guard end - start >= minimumDuration,
              siblings.filter({ $0.id != region.id }).allSatisfy({
                  end <= $0.startSeconds || start >= $0.endSeconds
              })
        else { return nil }
        return try? CineoTimelineRegion(id: region.id, startSeconds: start, endSeconds: end)
    }
}
