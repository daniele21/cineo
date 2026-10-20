import AppKit
import SwiftUI

/// Cineo Brand Kit v1.0 — source: Assets/Brand/cineo.tokens.json.
/// No embedded proprietary fonts: use installed Inter when available and the
/// native San Francisco fallback for accessibility and CLT-only builds.
enum CineoBrand {
    static let ink = Color(red: 9/255, green: 45/255, blue: 67/255)
    static let deepOcean = Color(red: 11/255, green: 79/255, blue: 106/255)
    static let ocean = Color(red: 16/255, green: 124/255, blue: 153/255)
    static let lagoon = Color(red: 41/255, green: 190/255, blue: 209/255)
    static let turquoise = Color(red: 85/255, green: 210/255, blue: 200/255)
    static let mint = Color(red: 152/255, green: 234/255, blue: 205/255)
    static let frost = Color(red: 221/255, green: 246/255, blue: 240/255)
    static let cloud = Color(red: 245/255, green: 250/255, blue: 249/255)
    static let muted = Color(red: 91/255, green: 113/255, blue: 128/255)

    static func displayFont(size: CGFloat) -> Font {
        NSFont(name: "InterDisplay-Bold", size: size) != nil
            ? .custom("InterDisplay-Bold", size: size)
            : .system(size: size, weight: .bold, design: .rounded)
    }

    static func bodyFont(size: CGFloat, weight: Font.Weight = .regular) -> Font {
        let face = weight == .semibold ? "Inter-SemiBold" : "Inter-Regular"
        return NSFont(name: face, size: size) != nil
            ? .custom(face, size: size)
            : .system(size: size, weight: weight)
    }

    static func image(named: String) -> NSImage? {
        guard let url = Bundle.main.url(forResource: named, withExtension: "png") else {
            return nil
        }
        return NSImage(contentsOf: url)
    }
}

/// Complete four-layer Cursor Zoom mark. Uses original supplied kit PNG, not
/// a replacement SF Symbol when the official resource exists in the app.
struct CineoBrandSymbol: View {
    var size: CGFloat = 46

    var body: some View {
        Group {
            if let image = CineoBrand.image(named: "CineoSymbol") {
                Image(nsImage: image).resizable().interpolation(.high)
                    .aspectRatio(contentMode: .fit)
            } else {
                Image(systemName: "square.stack.3d.up.fill")
                    .resizable().scaledToFit()
                    .foregroundStyle(CineoBrand.ocean)
            }
        }
        .frame(width: size, height: size)
        .accessibilityLabel("Cineo, Cursor Zoom")
    }
}
