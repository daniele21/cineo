import Foundation

/// A deterministic per-time representation of camera/stage composition.
/// No GUI framework or video backend is involved in camera evaluation.
public struct CineoScenePlan: Codable, Sendable, Equatable {
    public var outputWidth: Int
    public var outputHeight: Int
    public var paddingFraction: Double
    public var background: CineoRGB
    public var camera: [CineoCameraKeyframe]
    /// Optional click pulses, nil for all pre-effect Cineo projects.
    /// Explicitly not a duplicated mouse pointer. Renderer shares preview/export.
    public var clickHighlights: [CineoClickHighlight]?

    public init(outputWidth: Int, outputHeight: Int,
                paddingFraction: Double = 0.065,
                background: CineoRGB = .init(red: 0.08, green: 0.10, blue: 0.16),
                camera: [CineoCameraKeyframe] = [],
                clickHighlights: [CineoClickHighlight]? = nil) {
        self.outputWidth = outputWidth
        self.outputHeight = outputHeight
        self.paddingFraction = paddingFraction
        self.background = background
        self.camera = camera
        self.clickHighlights = clickHighlights
    }

    public func validate() throws {
        guard (2...8192).contains(outputWidth), outputWidth % 2 == 0,
              (2...8192).contains(outputHeight), outputHeight % 2 == 0,
              paddingFraction.isFinite, (0..<0.40).contains(paddingFraction),
              background.isValid,
              camera.count <= 100_000,
              (clickHighlights?.count ?? 0) <= 20_000
        else { throw CineoSceneError.invalidPlan }
        if let clickHighlights {
            var previous = -Double.infinity
            for marker in clickHighlights {
                guard marker.isValid, marker.time >= previous else {
                    throw CineoSceneError.invalidPlan
                }
                previous = marker.time
            }
        }
        var last = -Double.infinity
        for k in camera {
            guard k.time.isFinite, k.time >= 0, k.time > last,
                  k.zoom.isFinite, (1...3).contains(k.zoom),
                  k.focusX.isFinite, (0...1).contains(k.focusX),
                  k.focusY.isFinite, (0...1).contains(k.focusY)
            else { throw CineoSceneError.invalidPlan }
            last = k.time
        }
    }

    public func evaluate(time: Double, sourceWidth: Int, sourceHeight: Int) throws -> CineoSceneState {
        try validate()
        guard time.isFinite, time >= 0, sourceWidth > 0, sourceHeight > 0
        else { throw CineoSceneError.invalidSource }
        let current = cameraState(at: time)
        let fraction = 1 / current.zoom
        let cropX = min(max(0, current.focusX - fraction / 2), 1 - fraction)
        let cropY = min(max(0, current.focusY - fraction / 2), 1 - fraction)
        let canvasW = Double(outputWidth), canvasH = Double(outputHeight)
        let availW = canvasW * (1 - paddingFraction * 2)
        let availH = canvasH * (1 - paddingFraction * 2)
        let cropW = Double(sourceWidth) * fraction
        let cropH = Double(sourceHeight) * fraction
        let fit = min(availW / cropW, availH / cropH)
        let displayedW = cropW * fit, displayedH = cropH * fit
        return CineoSceneState(
            cropX: cropX, cropY: cropY, cropWidth: fraction, cropHeight: fraction,
            outputX: (canvasW - displayedW) / 2, outputY: (canvasH - displayedH) / 2,
            outputWidth: displayedW, outputHeight: displayedH
        )
    }

    private func cameraState(at seconds: Double) -> CineoCameraKeyframe {
        let overview = CineoCameraKeyframe(time: 0, zoom: 1, focusX: 0.5, focusY: 0.5)
        guard let first = camera.first else { return overview }
        if seconds >= camera[camera.count - 1].time { return camera[camera.count - 1] }
        var before = overview
        for after in camera {
            guard seconds >= after.time else {
                let range = after.time - before.time
                if range <= 0 { return after }
                let p = min(1, max(0, (seconds - before.time) / range))
                let eased = p * p * (3 - 2 * p)
                return CineoCameraKeyframe(
                    time: seconds,
                    zoom: exp(log(before.zoom) + (log(after.zoom) - log(before.zoom)) * eased),
                    focusX: before.focusX + (after.focusX - before.focusX) * eased,
                    focusY: before.focusY + (after.focusY - before.focusY) * eased
                )
            }
            before = after
        }
        return first
    }
}

public struct CineoClickHighlight: Codable, Sendable, Equatable {
    public let time: Double
    public let x: Double
    public let y: Double
    public init(time: Double, x: Double, y: Double) {
        self.time = time; self.x = x; self.y = y
    }
    public var isValid: Bool {
        time.isFinite && time >= 0 && x.isFinite && y.isFinite &&
        (0...1).contains(x) && (0...1).contains(y)
    }
}

public struct CineoRGB: Codable, Sendable, Equatable {
    public var red: Double
    public var green: Double
    public var blue: Double
    public init(red: Double, green: Double, blue: Double) {
        self.red = red; self.green = green; self.blue = blue
    }
    public var isValid: Bool {
        [red, green, blue].allSatisfy { $0.isFinite && (0...1).contains($0) }
    }
}

public struct CineoCameraKeyframe: Codable, Sendable, Equatable {
    public var time: Double
    public var zoom: Double
    public var focusX: Double
    public var focusY: Double
    public init(time: Double, zoom: Double, focusX: Double, focusY: Double) {
        self.time = time; self.zoom = zoom; self.focusX = focusX; self.focusY = focusY
    }
}

public struct CineoSceneState: Sendable, Equatable {
    /// Source-relative 0...1 coordinates, origin top-left.
    public let cropX: Double
    public let cropY: Double
    public let cropWidth: Double
    public let cropHeight: Double
    /// Output canvas pixels, origin bottom-left (Core Image layout).
    public let outputX: Double
    public let outputY: Double
    public let outputWidth: Double
    public let outputHeight: Double
}

public enum CineoSceneError: Error, Sendable {
    case invalidPlan
    case invalidSource
    case invalidDestination
    case unsupportedSourceTransform
    case readerFailed
    case writerFailed
    case invalidOutput
}
