import Foundation
import CineoEvents

/// Prepared once per recording, then shared by all preview and export frames.
/// The caller provides SOURCE time; deleted footage is skipped before lookup.
public struct CineoCursorOverlay: Sendable {
    private let track: CineoPointerMotionTrack
    public let sampleCount: Int

    public init(sidecar: CineoPointerSidecar) throws {
        try sidecar.validate()
        guard sidecar.cursorMode == .independentOverlay else {
            throw CineoEventsError.unsupportedSchema
        }
        let prepared = try CineoPointerMotionTrack(events: sidecar.events)
        track = prepared
        sampleCount = prepared.sampleCount
    }

    /// No extrapolation beyond captured telemetry or through missing samples.
    /// Short sampling gaps up to 250ms may interpolate, even across frame rates.
    public func position(atSourceTime time: Double) -> CineoPointerPosition? {
        track.position(at: time, interpolation: .easeInOut, maximumGap: 0.25)
    }
}
