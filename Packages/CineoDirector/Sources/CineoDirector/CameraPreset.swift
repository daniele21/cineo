import Foundation

/// User-facing cinematic intensity. Rule-based, fully local and reversible.
/// Presets affect *suggestions*, not already hand-edited camera segments.
public enum CameraPreset: String, CaseIterable, Codable, Sendable {
    case subtle
    case balanced
    case dynamic

    public var displayName: String {
        switch self {
        case .subtle: "Subtle"
        case .balanced: "Balanced"
        case .dynamic: "Dynamic"
        }
    }

    public var configuration: CameraPlanner.Configuration {
        var configuration = CameraPlanner.Configuration()
        switch self {
        case .subtle:
            configuration.clickZoom = 1.25
            configuration.resultZoom = 1.4
            configuration.leadTime = 0.45
            configuration.holdTime = 1.5
            configuration.minimumGapBetweenShots = 1.2
            configuration.duplicateSuppressionTime = 3.0
            configuration.maxShotsPerMinute = 8
        case .balanced:
            break
        case .dynamic:
            configuration.clickZoom = 1.65
            configuration.resultZoom = 1.85
            configuration.leadTime = 0.25
            configuration.holdTime = 0.9
            configuration.maximumClusterDuration = 2.0
            configuration.minimumGapBetweenShots = 0.4
            configuration.duplicateSuppressionTime = 1.0
            configuration.maxShotsPerMinute = 18
        }
        return configuration
    }
}
