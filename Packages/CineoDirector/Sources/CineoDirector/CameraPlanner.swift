import Foundation

/// Source-pixel positions should be normalized into [0, 1] before calling the planner.
/// No screen contents, typed text, or file paths are consumed or stored here.
public struct AttentionEvent: Codable, Sendable, Equatable {
    public enum Kind: String, Codable, Sendable { case click, dwell, result }
    public let time: Double
    public let x: Double
    public let y: Double
    public let kind: Kind

    public init(time: Double, x: Double, y: Double, kind: Kind) {
        self.time = time
        self.x = x
        self.y = y
        self.kind = kind
    }
}

/// A suggested camera hold, not final rendered frames. Editors may replace or remove any shot.
public struct CameraShot: Codable, Sendable, Equatable {
    public enum Reason: String, Codable, Sendable { case clickCluster, dwell, result }
    public let start: Double
    public let end: Double
    public let focusX: Double
    public let focusY: Double
    public let zoom: Double
    public let reason: Reason
}

public struct CameraPlanner: Sendable {
    public struct Configuration: Sendable {
        public var maximumEventGap: Double = 1.2
        public var maximumSpatialDistance: Double = 0.18
        public var leadTime: Double = 0.35
        public var holdTime: Double = 1.2
        public var minimumShotLength: Double = 0.8
        public var minimumGapBetweenShots: Double = 0.65
        public var clickZoom: Double = 1.4
        public var resultZoom: Double = 1.6
        public var maxShotsPerMinute: Int = 12
        public init() {}
    }

    public let configuration: Configuration
    public init(configuration: Configuration = Configuration()) { self.configuration = configuration }

    /// Pure, deterministic suggestions with bounded count and no overlapping holds.
    /// Invalid events are ignored rather than contaminating persisted plans.
    public func suggest(events: [AttentionEvent], duration: Double) -> [CameraShot] {
        guard duration.isFinite, duration > 0 else { return [] }
        let usable = events.filter {
            $0.time.isFinite && $0.x.isFinite && $0.y.isFinite &&
            $0.time >= 0 && $0.time < duration &&
            (0...1).contains($0.x) && (0...1).contains($0.y)
        }.sorted { $0.time < $1.time }
        guard !usable.isEmpty else { return [] }

        var groups: [[AttentionEvent]] = []
        for event in usable {
            if let lastGroup = groups.last, let last = lastGroup.last,
               event.time - last.time <= configuration.maximumEventGap,
               hypot(event.x - last.x, event.y - last.y) <= configuration.maximumSpatialDistance {
                groups[groups.count - 1].append(event)
            } else {
                groups.append([event])
            }
        }

        let maxShots = max(0, Int(ceil(duration / 60 * Double(max(0, configuration.maxShotsPerMinute)))))
        guard maxShots > 0 else { return [] }
        var shots: [CameraShot] = []
        for group in groups {
            guard let first = group.first, let last = group.last else { continue }
            let result = group.last(where: { $0.kind == .result })
            let target = result ?? group.last(where: { $0.kind == .dwell }) ?? last
            let reason: CameraShot.Reason = result != nil ? .result : (target.kind == .dwell ? .dwell : .clickCluster)
            let zoom = reason == .result ? configuration.resultZoom : configuration.clickZoom
            guard zoom.isFinite, zoom > 1 else { continue }

            let intendedStart = max(0, first.time - max(0, configuration.leadTime))
            let start = max(intendedStart, (shots.last?.end ?? -configuration.minimumGapBetweenShots) + configuration.minimumGapBetweenShots)
            let end = min(duration, max(start + configuration.minimumShotLength, last.time + configuration.holdTime))
            guard end > start, end - start >= min(configuration.minimumShotLength, duration) else { continue }
            // Keep edge targets inside the output frame; center is in normalized source space.
            let halfVisible = 0.5 / zoom
            let focusX = min(max(target.x, halfVisible), 1 - halfVisible)
            let focusY = min(max(target.y, halfVisible), 1 - halfVisible)
            shots.append(CameraShot(start: start, end: end, focusX: focusX, focusY: focusY, zoom: zoom, reason: reason))
            if shots.count >= maxShots { break }
        }
        return shots
    }
}
