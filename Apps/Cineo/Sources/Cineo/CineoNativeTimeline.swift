import SwiftUI
import AppKit
import AVFoundation
import ImageIO
import UniformTypeIdentifiers
import CineoProject

/// Native, non-destructive filmstrip. Only 12 bounded thumbnails are held and
/// requests are cancelled on source/cut change. The active AVPlayer stays the
/// authoritative decoder for interactive preview.
@MainActor
final class CineoFilmstripCache: ObservableObject {
    @Published private(set) var frames: [Int: NSImage] = [:]
    private var generator: AVAssetImageGenerator?
    private var key = ""

    func load(sourceURL: URL?, duration: Double, cuts: CineoCutList?) {
        guard let sourceURL, duration.isFinite, duration > 0 else {
            generator?.cancelAllCGImageGeneration()
            generator = nil
            key = ""
            frames = [:]
            return
        }
        let signature = sourceURL.path + "|" + String(duration) + "|" +
            (cuts?.retained.map { "\($0.start):\($0.end)" }.joined(separator: ",") ?? "")
        guard signature != key else { return }
        generator?.cancelAllCGImageGeneration()
        key = signature
        frames = [:]
        let asset = AVURLAsset(url: sourceURL)
        let newGenerator = AVAssetImageGenerator(asset: asset)
        newGenerator.appliesPreferredTrackTransform = true
        newGenerator.maximumSize = CGSize(width: 180, height: 110)
        newGenerator.requestedTimeToleranceBefore = CMTime(seconds: 0.1, preferredTimescale: 600)
        newGenerator.requestedTimeToleranceAfter = CMTime(seconds: 0.1, preferredTimescale: 600)
        generator = newGenerator
        let sampleTimes = (0..<12).map { idx in
            let output = duration * (Double(idx) + 0.5) / 12
            return cuts?.sourceTime(at: output) ?? output
        }
        let requests = sampleTimes.map { NSValue(time: CMTime(seconds: $0, preferredTimescale: 600)) }
        newGenerator.generateCGImagesAsynchronously(forTimes: requests) {
            [weak self] requested, cgImage, _, result, _ in
            guard result == .succeeded, let cgImage else { return }
            let actual = CMTimeGetSeconds(requested)
            guard actual.isFinite,
                  let index = sampleTimes.indices.min(by: {
                      abs(sampleTimes[$0] - actual) < abs(sampleTimes[$1] - actual)
                  })
            else { return }
            // Data is Sendable. NSImage construction is confined to MainActor.
            let data = NSMutableData()
            guard let destination = CGImageDestinationCreateWithData(
                data, UTType.png.identifier as CFString, 1, nil)
            else { return }
            CGImageDestinationAddImage(destination, cgImage, nil)
            guard CGImageDestinationFinalize(destination) else { return }
            let png = data as Data
            Task { @MainActor [weak self] in
                guard let self, self.key == signature, let image = NSImage(data: png) else { return }
                self.frames[index] = image
            }
        }
    }

    func clear() {
        generator?.cancelAllCGImageGeneration()
        generator = nil
        frames = [:]
        key = ""
    }
}

@MainActor
final class CineoTimelineDragIndicator: ObservableObject {
    @Published var activeID: String?
    @Published var dx: CGFloat = 0

    func reset() { activeID = nil; dx = 0 }
}

/// A single output-time ruler over filmstrip, zoom regions and music/cues.
/// No second timeline data model: zoom bands come from the actual scene keys.
struct CineoNativeTimelineView: View {
    @ObservedObject var editor: CineoEditorModel
    @StateObject private var thumbnails = CineoFilmstripCache()
    @StateObject private var drag = CineoTimelineDragIndicator()

    private var currentDuration: Double { max(0.1, editor.duration) }

    private func time(_ x: CGFloat, width: CGFloat) -> Double {
        guard let viewport = try? CineoTimelineViewport(
            startSeconds: 0, endSeconds: currentDuration, widthPixels: Double(width))
        else { return 0 }
        return viewport.time(atPixel: Double(x))
    }

    private func x(_ time: Double, width: CGFloat) -> CGFloat {
        CGFloat(max(0, min(1, time / currentDuration))) * width
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Label("Timeline", systemImage: "film.stack").font(.caption.weight(.semibold))
                Spacer()
                Text("Trascina lo zoom per spostarlo · clicca sul video per scorrere")
                    .font(.caption2).foregroundStyle(.secondary)
            }
            GeometryReader { geom in
                let width = geom.size.width
                ZStack(alignment: .topLeading) {
                    VStack(spacing: 4) {
                        HStack(spacing: 1) {
                            ForEach(0..<12, id: \.self) { index in
                                Group {
                                    if let frame = thumbnails.frames[index] {
                                        Image(nsImage: frame).resizable()
                                            .aspectRatio(contentMode: .fill)
                                    } else {
                                        Rectangle().fill(Color.secondary.opacity(0.10))
                                            .overlay(Image(systemName: "film")
                                                .font(.system(size: 10))
                                                .foregroundStyle(.secondary.opacity(0.4)))
                                    }
                                }
                                .frame(maxWidth: .infinity)
                                .frame(height: 50)
                                .clipped()
                            }
                        }
                        .frame(height: 50)
                        .background(Color.black.opacity(0.06))
                        .clipShape(RoundedRectangle(cornerRadius: 5))
                        .contentShape(Rectangle())
                        .gesture(DragGesture(minimumDistance: 0)
                            .onChanged { editor.scrub(time($0.location.x, width: width)) })

                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 4).fill(.secondary.opacity(0.09))
                            ForEach(editor.cameraZoomBands) { band in
                                let startX = x(band.startSeconds, width: width)
                                let bandWidth = max(8, x(band.endSeconds, width: width) - startX)
                                RoundedRectangle(cornerRadius: 4)
                                    .fill(CineoBrand.ocean.opacity(0.65))
                                    .overlay(alignment: .leading) {
                                        Text(String(format: "%.1f×", band.peakZoom))
                                            .font(.system(size: 10, weight: .semibold))
                                            .foregroundStyle(.white)
                                            .padding(.leading, 6)
                                            .lineLimit(1)
                                    }
                                    .frame(width: bandWidth, height: 25)
                                    .offset(x: startX + (drag.activeID == band.id ? drag.dx : 0))
                                    .gesture(DragGesture(minimumDistance: 4)
                                        .onChanged {
                                            drag.activeID = band.id
                                            drag.dx = $0.translation.width
                                        }
                                        .onEnded {
                                            editor.moveCameraZoomBand(
                                                id: band.id,
                                                deltaSeconds: Double($0.translation.width / max(1, width)) *
                                                              currentDuration)
                                            drag.reset()
                                        })
                                    .help("Trascina per spostare tutto lo zoom, senza modificare l'originale")
                            }
                        }
                        .frame(height: 25)
                        .help("Camera: blocchi di zoom generati dai keyframe reali")

                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 4).fill(.secondary.opacity(0.09))
                            if editor.musicAsset != nil {
                                let start = x(editor.musicSettings.offset, width: width)
                                let end = x(editor.musicSettings.offset + editor.musicClipLength, width: width)
                                RoundedRectangle(cornerRadius: 3)
                                    .fill(Color.teal.opacity(0.35))
                                    .frame(width: max(1, end - start))
                                    .offset(x: start)
                            }
                            ForEach(editor.musicCues, id: \.id) { cue in
                                Rectangle().fill(Color.purple.opacity(0.9))
                                    .frame(width: 2)
                                    .offset(x: x(cue.at, width: width))
                            }
                        }
                        .frame(height: 16)
                        .help("Musica e cue allineati alla stessa timeline")

                        HStack {
                            ForEach(0..<5, id: \.self) { i in
                                Text(String(format: "%.1fs", currentDuration * Double(i) / 4))
                                    .font(.system(size: 9, design: .monospaced))
                                    .foregroundStyle(.secondary)
                                if i != 4 { Spacer(minLength: 0) }
                            }
                        }
                        .frame(height: 14)
                        .contentShape(Rectangle())
                        .onTapGesture { point in editor.scrub(time(point.x, width: width)) }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    Rectangle().fill(.white).frame(width: 2, height: 97)
                        .shadow(color: .black.opacity(0.6), radius: 1)
                        .offset(x: x(editor.selectedTime, width: width))
                        .allowsHitTesting(false)
                }
            }
            .frame(height: 122)

            HStack(spacing: 10) {
                Label("Video", systemImage: "film").font(.caption2)
                Label("\(editor.cameraZoomBands.count) zoom", systemImage: "viewfinder")
                    .font(.caption2)
                Label(editor.musicAsset == nil ? "Musica assente" : "Musica", systemImage: "waveform")
                    .font(.caption2)
                Spacer()
                Button("Annulla spostamento zoom") { editor.undoCameraBandMove() }
                    .disabled(!editor.canUndoCameraBandMove || editor.isExporting)
                    .font(.caption2)
            }
            .foregroundStyle(.secondary)
        }
        .onAppear {
            thumbnails.load(sourceURL: editor.sourceURL, duration: editor.duration,
                            cuts: editor.cutList)
        }
        .onChange(of: editor.sourceURL) { _, _ in
            thumbnails.load(sourceURL: editor.sourceURL, duration: editor.duration,
                            cuts: editor.cutList)
        }
        .onChange(of: editor.duration) { _, _ in
            thumbnails.load(sourceURL: editor.sourceURL, duration: editor.duration,
                            cuts: editor.cutList)
        }
        .onDisappear { thumbnails.clear() }
    }
}
