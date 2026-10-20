import Foundation
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
        return image.composited(over: background).cropped(to: canvas)
    }
}
