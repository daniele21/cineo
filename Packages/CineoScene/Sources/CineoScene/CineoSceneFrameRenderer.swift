import Foundation
#if canImport(CoreImage) && canImport(CoreGraphics)
import CoreImage
import CoreGraphics

/// Shared still-frame compositor: preview and export MUST call this exact
/// function with the same output-time camera plan. No approximation.
public enum CineoSceneFrameRenderer {
    public static func compose(_ source: CIImage, at seconds: Double,
                               with plan: CineoScenePlan) throws -> CIImage {
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
        return output
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
