import Foundation

/// Mechanical safety/pace measurements, NOT a perceptual or storytelling score.
/// A passing report cannot establish that a video "looks cinematic".
public struct CineoCameraQualityMetrics: Codable, Sendable {
    public let duration: Double
    public let shotCount: Int
    public let shotsPerMinute: Double
    public let minimumGap: Double?
    public let maximumZoom: Double
    public let violations: [String]

    public var isStructurallySafe: Bool { violations.isEmpty }
}

public enum CineoCameraQuality {
    public static func measure(shots: [CameraShot], duration: Double,
                               maxShotsPerMinute: Int = 18,
                               minimumGap: Double = 0.20) -> CineoCameraQualityMetrics {
        guard duration.isFinite, duration > 0 else {
            return CineoCameraQualityMetrics(duration: duration, shotCount: shots.count,
                shotsPerMinute: 0, minimumGap: nil, maximumZoom: 1,
                violations: ["invalid_duration"])
        }
        let ordered = shots.sorted { $0.start < $1.start }
        var violations: [String] = []
        var smallestGap: Double?
        for (index, shot) in ordered.enumerated() {
            if !shot.start.isFinite || !shot.end.isFinite ||
                shot.start < 0 || shot.start >= shot.end || shot.end > duration {
                violations.append("shot_bounds_\(index)")
            }
            if !shot.zoom.isFinite || shot.zoom <= 1 || shot.zoom > 3 ||
               !shot.focusX.isFinite || !shot.focusY.isFinite ||
               !(0...1).contains(shot.focusX) || !(0...1).contains(shot.focusY) {
                violations.append("invalid_camera_\(index)")
            } else {
                // A shot must never ask to show pixels beyond the source image.
                let half = 0.5 / shot.zoom
                if shot.focusX < half - 1e-9 || shot.focusX > 1-half + 1e-9 ||
                   shot.focusY < half - 1e-9 || shot.focusY > 1-half + 1e-9 {
                    violations.append("unsafe_crop_\(index)")
                }
            }
            if index > 0 {
                let gap = shot.start - ordered[index - 1].end
                smallestGap = smallestGap.map { min($0, gap) } ?? gap
                if gap < minimumGap - 1e-9 { violations.append("insufficient_wide_gap_\(index)") }
            }
            // Rolling 60-second budget, aligned with CameraPlanner.
            if ordered.filter({ $0.start <= shot.start && $0.start > shot.start - 60 }).count > maxShotsPerMinute {
                violations.append("shot_rate_\(index)")
            }
        }
        return CineoCameraQualityMetrics(duration: duration, shotCount: shots.count,
            shotsPerMinute: Double(shots.count) * 60 / duration,
            minimumGap: smallestGap,
            maximumZoom: ordered.map(\.zoom).max() ?? 1,
            violations: violations)
    }
}
