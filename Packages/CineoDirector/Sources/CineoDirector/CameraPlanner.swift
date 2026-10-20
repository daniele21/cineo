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
        /// Prevent one long stream of clicks from becoming a single multi-minute shot.
        public var maximumClusterDuration: Double = 3.0
        /// Avoid repeated camera movement on the same unchanged control.
        public var duplicateSuppressionTime: Double = 2.0
        public var duplicateSpatialDistance: Double = 0.12
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
    /// Invalid events or unsafe configuration are ignored; suggestions never
    /// change the recording and can be overridden individually by the editor.
    public func suggest(events: [AttentionEvent], duration: Double) -> [CameraShot] {
        let config = configuration
        guard duration.isFinite, duration > 0,
              config.maximumEventGap.isFinite, config.maximumEventGap >= 0,
              config.maximumSpatialDistance.isFinite, config.maximumSpatialDistance >= 0,
              config.maximumClusterDuration.isFinite, config.maximumClusterDuration > 0,
              config.duplicateSuppressionTime.isFinite, config.duplicateSuppressionTime >= 0,
              config.duplicateSpatialDistance.isFinite, config.duplicateSpatialDistance >= 0,
              config.leadTime.isFinite, config.leadTime >= 0,
              config.holdTime.isFinite, config.holdTime >= 0,
              config.minimumShotLength.isFinite, config.minimumShotLength > 0,
              config.minimumGapBetweenShots.isFinite, config.minimumGapBetweenShots >= 0,
              config.clickZoom.isFinite, config.clickZoom > 1, config.clickZoom <= 3,
              config.resultZoom.isFinite, config.resultZoom > 1, config.resultZoom <= 3,
              config.maxShotsPerMinute > 0
        else { return [] }

        // Sort total order rather than relying on input order for same-time events.
        // A result anchor wins over dwell and click at the same moment.
        let usable = events.filter {
            $0.time.isFinite && $0.x.isFinite && $0.y.isFinite &&
            $0.time >= 0 && $0.time < duration &&
            (0...1).contains($0.x) && (0...1).contains($0.y)
        }.sorted {
            if $0.time != $1.time { return $0.time < $1.time }
            if $0.kind != $1.kind { return $0.kind.priority < $1.kind.priority }
            if $0.x != $1.x { return $0.x < $1.x }
            return $0.y < $1.y
        }
        guard !usable.isEmpty else { return [] }

        var groups: [[AttentionEvent]] = []
        for event in usable {
            if let current = groups.last, let first = current.first,
               let last = current.last,
               event.time - last.time <= config.maximumEventGap,
               event.time - first.time <= config.maximumClusterDuration,
               hypot(event.x - last.x, event.y - last.y) <= config.maximumSpatialDistance {
                groups[groups.count - 1].append(event)
            } else {
                groups.append([event])
            }
        }

        var shots: [CameraShot] = []
        for group in groups {
            guard let first = group.first, let last = group.last else { continue }
            // Results take precedence over clicks. Later results win; stable sort
            // gives a reproducible answer even when telemetry ordering varies.
            let result = group.last(where: { $0.kind == .result })
            let target = result ?? group.last(where: { $0.kind == .dwell }) ?? last
            let reason: CameraShot.Reason = result != nil ? .result : (target.kind == .dwell ? .dwell : .clickCluster)
            let zoom = reason == .result ? config.resultZoom : config.clickZoom

            if let previous = shots.last, reason != .result, previous.reason != .result,
               first.time - previous.start <= config.duplicateSuppressionTime,
               hypot(target.x - previous.focusX, target.y - previous.focusY) <= config.duplicateSpatialDistance {
                continue
            }
            let intendedStart = max(0, first.time - config.leadTime)
            let start = max(intendedStart, (shots.last?.end ?? -config.minimumGapBetweenShots) + config.minimumGapBetweenShots)
            guard start < duration else { continue }
            let end = min(duration, max(start + config.minimumShotLength, last.time + config.holdTime))
            guard end > start, end - start >= min(config.minimumShotLength, duration) else { continue }

            // Rolling window rather than a budget prorated from total clip duration:
            // a 3-minute clip must not cram all allowed shots into its first 20 s.
            let recentCount = shots.filter { $0.start > start - 60 }.count
            guard recentCount < config.maxShotsPerMinute else { continue }

            let halfVisible = 0.5 / zoom
            let focusX = min(max(target.x, halfVisible), 1 - halfVisible)
            let focusY = min(max(target.y, halfVisible), 1 - halfVisible)
            shots.append(CameraShot(start: start, end: end, focusX: focusX, focusY: focusY, zoom: zoom, reason: reason))
        }
        return shots
    }
}

private extension AttentionEvent.Kind {
    var priority: Int {
        switch self {
        case .click: 0
        case .dwell: 1
        case .result: 2
        }
    }
}
