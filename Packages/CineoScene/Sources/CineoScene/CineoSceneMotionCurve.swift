import Foundation

/// Playback/export-independent motion vocabulary. Curves are evaluated from
/// their timestamp, never from the previous rendered frame or display FPS.
public enum CineoSceneMotionPreset: String, Codable, Sendable, CaseIterable {
    case classic
    case focused
    case cinematic
}

public enum CineoSceneMotionCurve {
    /// A normalized progress curve. Exact endpoints are invariant and
    /// evaluating timestamps in any order yields identical results.
    public static func progress(_ fraction: Double,
                                preset: CineoSceneMotionPreset = .classic) -> Double {
        guard fraction.isFinite else { return 0 }
        let x = max(0, min(1, fraction))
        if x == 0 || x == 1 { return x }
        switch preset {
        case .classic:
            // Preserve previous scene.json geometry bit-for-bit.
            return x * x * (3 - 2 * x)
        case .focused:
            // Quick acquisition with a readable settling hold.
            return 1 - pow(1 - x, 3)
        case .cinematic:
            // Closed-form critically damped response, normalized to [0,1].
            // Unlike frame-stepped springs, seeks and exports are deterministic.
            let rate = 8.0
            let denominator = 1 - exp(-rate) * (1 + rate)
            let value = 1 - exp(-rate * x) * (1 + rate * x)
            return max(0, min(1, value / denominator))
        }
    }
}
