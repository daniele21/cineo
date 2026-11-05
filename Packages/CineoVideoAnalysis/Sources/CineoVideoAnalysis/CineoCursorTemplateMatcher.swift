import Foundation
import CoreGraphics

/// Experimental CPU-only cursor patch matching for tiny screen-recording
/// pointers that generic Vision object tracking cannot reliably follow.
/// A user-chosen cursor tip is mandatory. Never infer clicks or erase pixels.
struct CineoCursorTemplateMatcher {
    struct Match: Sendable {
        let x: Double
        let y: Double
        let confidence: Double
        let errorPixels: Double
    }

    private let width: Int
    private let height: Int
    private let sampleOffsets: [(x: Int, y: Int)]
    private let reference: [Int]
    private let patchLeft = -5
    private let patchTop = -5
    private let patchWidth = 20
    private let patchHeight = 27

    init?(seed: CGImage, hotspotX: Double, hotspotY: Double) {
        guard let gray = Self.grayscale(seed), seed.width >= 100, seed.height >= 80
        else { return nil }
        width = seed.width
        height = seed.height
        let centerX = Int((hotspotX * Double(width)).rounded())
        let centerY = Int((hotspotY * Double(height)).rounded())
        guard centerX + patchLeft >= 0, centerY + patchTop >= 0,
              centerX + patchLeft + patchWidth < width,
              centerY + patchTop + patchHeight < height
        else { return nil }
        var offsets: [(x: Int, y: Int)] = []
        var intensity: [Int] = []
        for dy in stride(from: 0, to: patchHeight, by: 2) {
            for dx in stride(from: 0, to: patchWidth, by: 2) {
                let px = centerX + patchLeft + dx
                let py = centerY + patchTop + dy
                offsets.append((patchLeft + dx, patchTop + dy))
                intensity.append(Int(gray[py * width + px]))
            }
        }
        sampleOffsets = offsets
        reference = intensity
    }

    func locate(in frame: CGImage, aroundX x: Double, y: Double) -> Match? {
        guard frame.width == width, frame.height == height,
              let gray = Self.grayscale(frame),
              x.isFinite, y.isFinite else { return nil }
        let centerX = Int((x * Double(width)).rounded())
        let centerY = Int((y * Double(height)).rounded())
        let minX = -patchLeft
        let maxX = width - patchLeft - patchWidth - 1
        let minY = -patchTop
        let maxY = height - patchTop - patchHeight - 1

        func error(_ px: Int, _ py: Int, _ cutoff: Int) -> Int {
            var sum = 0
            for i in sampleOffsets.indices {
                let delta = Int(gray[(py + sampleOffsets[i].y) * width +
                                     px + sampleOffsets[i].x]) - reference[i]
                sum += delta * delta
                if sum >= cutoff { return sum }
            }
            return sum
        }

        var bestX = centerX, bestY = centerY
        var best = Int.max
        func scan(radius: Int, stride step: Int) {
            let loX = max(minX, centerX - radius), hiX = min(maxX, centerX + radius)
            let loY = max(minY, centerY - radius), hiY = min(maxY, centerY + radius)
            guard loX <= hiX && loY <= hiY else { return }
            for py in Swift.stride(from: loY, through: hiY, by: step) {
                for px in Swift.stride(from: loX, through: hiX, by: step) {
                    let candidate = error(px, py, best)
                    if candidate < best {
                        best = candidate
                        bestX = px
                        bestY = py
                    }
                }
            }
        }
        scan(radius: 65, stride: 3)
        if best > sampleOffsets.count * 28 * 28 {
            scan(radius: 145, stride: 5)
        }
        guard best != Int.max else { return nil }
        let coarseX = bestX, coarseY = bestY
        for py in max(minY, coarseY - 5)...min(maxY, coarseY + 5) {
            for px in max(minX, coarseX - 5)...min(maxX, coarseX + 5) {
                let candidate = error(px, py, best)
                if candidate < best {
                    best = candidate
                    bestX = px
                    bestY = py
                }
            }
        }
        let rmse = sqrt(Double(best) / Double(sampleOffsets.count))
        guard rmse <= 40 else { return nil }
        return .init(x: Double(bestX) / Double(width),
                     y: Double(bestY) / Double(height),
                     confidence: min(1, max(0, 1 - rmse / 100)),
                     errorPixels: rmse)
    }

    /// Normalized top-left pixel order, independent of CGImage storage layout.
    private static func grayscale(_ image: CGImage) -> [UInt8]? {
        let width = image.width, height = image.height
        guard width > 0, height > 0,
              width <= 1920, height <= 1920 else { return nil }
        var rgba = [UInt8](repeating: 0, count: width * height * 4)
        let succeeded = rgba.withUnsafeMutableBytes { bytes -> Bool in
            guard let context = CGContext(
                data: bytes.baseAddress, width: width, height: height,
                bitsPerComponent: 8, bytesPerRow: width * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGBitmapInfo.byteOrder32Big.rawValue |
                            CGImageAlphaInfo.premultipliedLast.rawValue)
            else { return false }
            context.translateBy(x: 0, y: CGFloat(height))
            context.scaleBy(x: 1, y: -1)
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard succeeded else { return nil }
        var result = [UInt8](repeating: 0, count: width * height)
        for n in result.indices {
            let start = n * 4
            let value = 77 * Int(rgba[start]) + 150 * Int(rgba[start + 1]) +
                        29 * Int(rgba[start + 2])
            result[n] = UInt8(min(255, value >> 8))
        }
        return result
    }
}
