import CineoEvents
import Foundation
import ScreenCaptureKit
import CoreMedia

struct CineoPointerRawClick {
    let hostSeconds: Double
    let x: Double
    let y: Double
    let kind: CineoPointerEvent.Kind
}

/// Receives screen sample metadata only; does not retain or inspect pixels.
/// ScreenCaptureKit timestamps use host-time seconds on macOS.
final class CineoFirstFrameObserver: NSObject, SCStreamOutput, @unchecked Sendable {
    private let lock = NSLock()
    private var anchor: Double?

    var firstFrameHostSeconds: Double? {
        lock.lock()
        defer { lock.unlock() }
        return anchor
    }

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer,
                of type: SCStreamOutputType) {
        guard type == .screen, CMSampleBufferIsValid(sampleBuffer) else { return }
        let pts = CMSampleBufferGetPresentationTimeStamp(sampleBuffer).seconds
        guard pts.isFinite, pts > 0 else { return }
        lock.lock()
        if anchor == nil { anchor = pts }
        lock.unlock()
    }
}
