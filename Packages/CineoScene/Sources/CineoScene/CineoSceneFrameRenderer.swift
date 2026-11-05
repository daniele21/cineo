import Foundation
#if canImport(CoreImage) && canImport(CoreGraphics)
import CoreImage
import CoreGraphics

/// Shared still-frame compositor: preview and export MUST call this exact
/// function with the same output-time camera plan. No approximation.
public enum CineoSceneFrameRenderer {
    public static func compose(_ source: CIImage, at seconds: Double,
                               with plan: CineoScenePlan,
                               cursor: CineoCursorOverlay? = nil,
                               cursorSourceSeconds: Double? = nil) throws -> CIImage {
        let state = try plan.evaluate(
            time: seconds,
            sourceWidth: Int(source.extent.width),
            sourceHeight: Int(source.extent.height)
        )
        let extent = source.extent
        let crop = CGRect(
            x: extent.minX + state.cropX * extent.width,
            y: extent.minY + (1 - state.cropY - state.cropHeight) * extent.height,
            width: state.cropWidth * extent.width,
            height: state.cropHeight * extent.height
        )
        guard crop.width > 0, crop.height > 0 else { throw CineoSceneError.invalidSource }
        let scale = state.outputWidth / crop.width
        let canvas = CGRect(x: 0, y: 0,
                            width: CGFloat(plan.outputWidth), height: CGFloat(plan.outputHeight))
        let background = CIImage(color: CIColor(
            red: plan.background.red, green: plan.background.green,
            blue: plan.background.blue
        )).cropped(to: canvas)
        let image = source
            .cropped(to: crop)
            .transformed(by: CGAffineTransform(translationX: -crop.minX, y: -crop.minY))
            .transformed(by: CGAffineTransform(scaleX: scale, y: scale))
            .transformed(by: CGAffineTransform(
                translationX: state.outputX, y: state.outputY
            ))
        var output = image.composited(over: background).cropped(to: canvas)
        if let click = plan.clickHighlights?.last(where: {
            seconds >= $0.time && seconds - $0.time <= 0.55
        }) {
            // Click pulses are part of the same Core Image pipeline used
            // for timeline preview and H.264. No second cursor is painted:
            // ScreenCaptureKit's existing pointer remains untouched.
            let rx = (click.x - state.cropX) / state.cropWidth
            let ry = (click.y - state.cropY) / state.cropHeight
            if (0...1).contains(rx), (0...1).contains(ry),
               let ring = ringImage(elapsed: seconds - click.time) {
                let centerX = state.outputX + rx * state.outputWidth
                let centerY = state.outputY + (1 - ry) * state.outputHeight
                let layer = ring.transformed(by: CGAffineTransform(
                    translationX: centerX - 64, y: centerY - 64))
                output = layer.composited(over: output).cropped(to: canvas)
            }
        }
        // The independent pointer is rendered ONLY when the recording sidecar
        // explicitly declares that ScreenCaptureKit hid the original pointer.
        if let pointer = cursor?.position(atSourceTime: cursorSourceSeconds ?? seconds) {
            let rx = (pointer.x - state.cropX) / state.cropWidth
            let ry = (pointer.y - state.cropY) / state.cropHeight
            if (0...1).contains(rx), (0...1).contains(ry),
               let arrow = pointerImage() {
                let hotspotX = state.outputX + rx * state.outputWidth
                let hotspotY = state.outputY + (1 - ry) * state.outputHeight
                // Cursor path hotspot is (3,59) in the native image; keep
                // that exact pixel aligned to its source-normalized coordinate.
                let placed = arrow.transformed(by: CGAffineTransform(
                    translationX: hotspotX - 3, y: hotspotY - 59))
                output = placed.composited(over: output).cropped(to: canvas)
            }
        }
        return output
    }

    /// Independently designed native vector glyph. No upstream cursor artwork.
    private static func pointerImage() -> CIImage? {
        let width = 48, height = 64
        guard let context = CGContext(data: nil, width: width, height: height,
            bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        let shape = CGMutablePath()
        shape.move(to: CGPoint(x: 3, y: 59)) // exact click hotspot
        shape.addLine(to: CGPoint(x: 4, y: 12))
        shape.addLine(to: CGPoint(x: 15, y: 24))
        shape.addLine(to: CGPoint(x: 23, y: 7))
        shape.addLine(to: CGPoint(x: 30, y: 11))
        shape.addLine(to: CGPoint(x: 22, y: 27))
        shape.addLine(to: CGPoint(x: 41, y: 27))
        shape.closeSubpath()
        context.addPath(shape)
        context.setFillColor(CGColor(gray: 0.985, alpha: 1))
        context.setStrokeColor(CGColor(gray: 0.09, alpha: 1))
        context.setLineJoin(.round)
        context.setLineWidth(3)
        context.drawPath(using: .fillStroke)
        guard let image = context.makeImage() else { return nil }
        return CIImage(cgImage: image)
    }

    /// Small transparent vector-derived bitmap rendered only during click
    /// pulses. The source pixel buffer is never changed or re-encoded here.
    private static func ringImage(elapsed: Double) -> CIImage? {
        let size = 128
        guard elapsed.isFinite, elapsed >= 0, elapsed <= 0.55,
              let context = CGContext(data: nil, width: size, height: size,
                  bitsPerComponent: 8, bytesPerRow: 0,
                  space: CGColorSpaceCreateDeviceRGB(),
                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        let t = elapsed / 0.55
        let easing = 1 - (1 - t) * (1 - t)
        let radius = CGFloat(16 + easing * 34)
        let alpha = CGFloat(max(0, 0.90 * (1 - t)))
        context.setStrokeColor(CGColor(red: 41 / 255, green: 190 / 255,
                                       blue: 209 / 255, alpha: alpha))
        context.setLineWidth(4.5)
        context.strokeEllipse(in: CGRect(x: 64 - radius, y: 64 - radius,
                                         width: 2 * radius, height: 2 * radius))
        guard let image = context.makeImage() else { return nil }
        return CIImage(cgImage: image)
    }
}

#endif
