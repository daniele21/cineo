import SwiftUI
import ScreenCaptureKit
import AVFoundation

// Compile-only framework references. This example does not request OS permissions.
private enum FrameworkAvailability {
    static let captureType = SCStream.self
    static let exportType = AVAssetExportSession.self
}

@main
struct CineoCLTProofApp: App {
    var body: some Scene {
        WindowGroup("Cineo CLT proof") {
            VStack(alignment: .leading, spacing: 14) {
                Text("Cineo").font(.largeTitle.bold())
                Text("Native app built using SwiftPM and macOS Command Line Tools.")
                Label("SwiftUI", systemImage: "checkmark.circle")
                Label("ScreenCaptureKit", systemImage: "display")
                Label("AVFoundation", systemImage: "film")
                Text("Technical build proof only — not a working recorder.")
                    .foregroundStyle(.secondary)
            }
            .padding(26)
            .frame(minWidth: 500, minHeight: 260)
        }
    }
}
