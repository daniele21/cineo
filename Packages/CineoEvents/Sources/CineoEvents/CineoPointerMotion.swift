import Foundation

/// A frame-time cursor position in source-normalized coordinates (top-left origin).
/// Pure source telemetry evaluation: no wall-clock state and no inferred click path.
public struct CineoPointerPosition: Equatable, Sendable {
    public let x: Double
    public let y: Double
    public let anchoredToClick: Bool

    public init(x: Double, y: Double, anchoredToClick: Bool) {
        self.x = x
        self.y = y
        self.anchoredToClick = anchoredToClick
    }
}

public enum CineoPointerInterpolation: Sendable {
    case linear
    case easeInOut
}

/// Prepared once per recording, evaluated at arbitrary presentation timestamps.
///
/// Important: movement cannot be reconstructed from legacy click-only sidecars.
/// Missing positions and long telemetry gaps return nil instead of fabricating
/// a path across a cut, pause, monitor change or unrecorded interval.
public struct CineoPointerMotionTrack: Sendable {
    private let samples: [CineoPointerEvent]

    public init(events: [CineoPointerEvent]) throws {
        guard events.allSatisfy(\.isValid),
              zip(events, events.dropFirst()).allSatisfy({
                  $0.0.sourceSeconds <= $0.1.sourceSeconds
              })
        else { throw CineoEventsError.invalidEvent }
        samples = events.filter { $0.kind == .moved || $0.kind == .leftClick || $0.kind == .rightClick }
    }

    public var sampleCount: Int { samples.count }

    /// - Parameters:
    ///   - maximumGap: movement interpolation is disabled across larger gaps.
    /// - Returns: nil before/after telemetry or when no motion evidence exists.
    public func position(
        at sourceSeconds: Double,
        interpolation: CineoPointerInterpolation = .linear,
        maximumGap: Double = 0.25
    ) -> CineoPointerPosition? {
        guard sourceSeconds.isFinite, sourceSeconds >= 0,
              maximumGap.isFinite, maximumGap > 0,
              !samples.isEmpty
        else { return nil }

        // Lower-bound binary search; never depend on previously rendered frames.
        var low = 0
        var high = samples.count
        while low < high {
            let mid = low + (high - low) / 2
            if samples[mid].sourceSeconds < sourceSeconds {
                low = mid + 1
            } else {
                high = mid
            }
        }

        if low < samples.count, samples[low].sourceSeconds == sourceSeconds {
            // Clicks are exact anchors even if a movement event shares a timestamp.
            var index = low
            var chosen = samples[low]
            while index < samples.count, samples[index].sourceSeconds == sourceSeconds {
                if samples[index].kind == .leftClick || samples[index].kind == .rightClick {
                    chosen = samples[index]
                    break
                }
                chosen = samples[index]
                index += 1
            }
            return .init(x: chosen.x, y: chosen.y,
                         anchoredToClick: chosen.kind == .leftClick || chosen.kind == .rightClick)
        }

        guard low > 0, low < samples.count else { return nil }
        let before = samples[low - 1]
        let after = samples[low]
        let gap = after.sourceSeconds - before.sourceSeconds
        guard gap > 0, gap <= maximumGap,
              before.kind == .moved || after.kind == .moved
        else { return nil }

        let fraction = (sourceSeconds - before.sourceSeconds) / gap
        let weight: Double
        switch interpolation {
        case .linear: weight = fraction
        case .easeInOut: weight = fraction * fraction * (3 - 2 * fraction)
        }
        // A convex interpolation cannot overshoot the source coordinates.
        return .init(x: before.x + (after.x - before.x) * weight,
                     y: before.y + (after.y - before.y) * weight,
                     anchoredToClick: false)
    }
}
