import Foundation
import SwiftUI
import AVFoundation
import AppKit
import CoreImage
import CineoScene
import CineoProject
import CryptoKit

@MainActor
final class CineoEditorModel: ObservableObject {
    enum Mode: String, CaseIterable {
        case manual = "Manuale"
        case assisted = "Assistito"
    }

    @Published var sourceURL: URL?
    @Published private(set) var projectURL: URL?
    @Published private(set) var isSavingProject = false
    @Published var title = ""
    @Published var sourcePixelWidth = 1512
    @Published var sourcePixelHeight = 982
    @Published var mode: Mode = .manual
    @Published var duration: Double = 0
    @Published var selectedTime: Double = 0
    @Published var zoom: Double = 1
    @Published var focusX: Double = 0.5
    @Published var focusY: Double = 0.5
    @Published var padding: Double = 0.06
    @Published var portrait = false
    @Published var style = "Dark"
    @Published var preview: NSImage?
    @Published var status = "Apri una registrazione per iniziare."
    @Published var loadingPreview = false
    @Published var isExporting = false
    @Published var exportProgress: Double = 0
    @Published var outputURL: URL?
    @Published var keyframes: [CineoCameraKeyframe] = []

    private var previewTask: Task<Void, Never>?
    private var previewRequest = UUID()
    private var exportTask: Task<Void, Never>?

    var outputWidth: Int { portrait ? 1080 : 1920 }
    var outputHeight: Int { portrait ? 1920 : 1080 }
    var currentPlan: CineoScenePlan {
        let color: CineoRGB = switch style {
        case "Light": .init(red: 0.91, green: 0.93, blue: 0.97)
        case "Black": .init(red: 0.015, green: 0.017, blue: 0.025)
        default: .init(red: 0.09, green: 0.12, blue: 0.19)
        }
        return CineoScenePlan(
            outputWidth: outputWidth, outputHeight: outputHeight,
            paddingFraction: padding, background: color,
            camera: keyframes.sorted { $0.time < $1.time }
        )
    }

    func open(_ url: URL) async {
        guard !isExporting && !isSavingProject else { return }
        status = "Caricamento del video o progetto…"
        previewTask?.cancel()
        preview = nil
        sourceURL = nil
        projectURL = nil
        outputURL = nil
        do {
            var mediaURL = url
            var openedProject: CineoManifest?
            if url.pathExtension.lowercased() == "cineo" {
                let manifest = try CineoProjectStore().load(from: url)
                // v0 renderer supports one original untrimmed source only.
                guard manifest.sources.count == 1, manifest.edits.count == 1,
                      manifest.edits[0].sourceID == manifest.sources[0].id,
                      manifest.edits[0].sourceStart == 0,
                      manifest.edits[0].speed == 1,
                      abs(manifest.edits[0].sourceEnd - manifest.sources[0].duration) < 0.001
                else {
                    status = "Questo progetto usa tagli o clip multiple non ancora supportati da Studio."
                    return
                }
                mediaURL = url.appendingPathComponent(manifest.sources[0].relativePath)
                openedProject = manifest
            }
            let asset = AVURLAsset(url: mediaURL)
            guard let track = try await asset.loadTracks(withMediaType: .video).first else {
                status = "Il file non contiene una traccia video."
                return
            }
            let t = try await asset.load(.duration)
            let size = try await track.load(.naturalSize)
            let transform = try await track.load(.preferredTransform)
            guard t.isNumeric, t.seconds > 0, size.width > 0, size.height > 0,
                  transform.isIdentity else {
                status = "Formato video non ancora supportato dall'editor Core Image."
                return
            }
            duration = t.seconds
            sourcePixelWidth = Int(size.width)
            sourcePixelHeight = Int(size.height)
            selectedTime = 0
            zoom = 1
            focusX = 0.5
            focusY = 0.5
            padding = 0.06
            portrait = false
            style = "Dark"
            keyframes = []
            title = openedProject?.title ?? url.lastPathComponent
            sourceURL = mediaURL
            projectURL = openedProject == nil ? nil : url
            restorePlan()
            status = projectURL == nil
                ? "Regola lo zoom o scegli un punto. Puoi salvare tutto in un progetto Cineo."
                : "Progetto Cineo riaperto: puoi modificare ed esportare senza cambiare l'originale."
            refreshPreview()
        } catch {
            status = "Impossibile aprire video o progetto: \(error.localizedDescription)"
        }
    }

    /// Import an already inspected recording into an independent, crash-safe
    /// versioned project. The original recording is not moved or overwritten.
    func saveAsProject() {
        guard let source = sourceURL, projectURL == nil,
              !isSavingProject, !isExporting, duration.isFinite, duration > 0 else { return }
        let projects = FileManager.default.urls(for: .moviesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Cineo/Projects", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: projects, withIntermediateDirectories: true)
        } catch {
            status = "Impossibile creare la cartella progetti: \(error.localizedDescription)"
            return
        }
        let location = projects.appendingPathComponent(UUID().uuidString + ".cineo", isDirectory: true)
        let width = sourcePixelWidth, height = sourcePixelHeight
        let length = duration, name = title
        isSavingProject = true
        status = "Copio il video nel progetto Cineo senza modificare l'originale…"
        Task {
            do {
                let manifest = try await Task.detached(priority: .userInitiated) {
                    try CineoRecordingImporter().createProject(
                        from: source, at: location,
                        width: width, height: height,
                        durationSeconds: length, title: name
                    )
                }.value
                let savedSource = location.appendingPathComponent(manifest.sources[0].relativePath)
                projectURL = location
                sourceURL = savedSource
                if savePlan() {
                    status = "Progetto Cineo salvato: \(location.lastPathComponent)"
                }
            } catch {
                status = "Salvataggio progetto fallito: \(error.localizedDescription). Il video originale è intatto."
            }
            isSavingProject = false
        }
    }

    func close() {
        guard !isExporting else {
            status = "Termina o annulla l'esportazione prima di chiudere l'editor."
            return
        }
        previewTask?.cancel()
        previewTask = nil
        preview = nil
        sourceURL = nil
        projectURL = nil
        status = ""
    }

    func scrub(_ seconds: Double) {
        selectedTime = min(max(seconds, 0), max(0, duration - 0.05))
        if let state = try? currentPlan.evaluate(
            time: selectedTime, sourceWidth: sourcePixelWidth, sourceHeight: sourcePixelHeight
        ) {
            zoom = 1 / state.cropWidth
            focusX = state.cropX + state.cropWidth / 2
            focusY = state.cropY + state.cropHeight / 2
        }
        refreshPreview()
    }

    func changeZoom(_ newZoom: Double) {
        zoom = min(2.5, max(1, newZoom))
        saveKeyframe()
    }

    func changeFocus(x: Double? = nil, y: Double? = nil) {
        if let x { focusX = min(1, max(0, x)) }
        if let y { focusY = min(1, max(0, y)) }
        // In Assisted mode, picking a target is not an edit yet: only the
        // explicit "Suggest zoom" action should write camera keyframes.
        // Otherwise the target click would create a keyframe and block its
        // own assistive animation with the manual-override collision guard.
        if mode == .manual { saveKeyframe() }
    }

    func choosePoint(x: Double, y: Double) {
        guard let state = try? currentPlan.evaluate(
            time: selectedTime, sourceWidth: sourcePixelWidth, sourceHeight: sourcePixelHeight
        ) else { return }
        guard x >= 0, x <= 1, y >= 0, y <= 1 else { return }
        // Convert canvas coords into cropped source coords; the scene is
        // centred so outputX/Y are symmetric for our fixed stage canvas.
        let stageX = x * Double(outputWidth)
        let stageY = y * Double(outputHeight)
        guard stageX >= state.outputX, stageX <= state.outputX + state.outputWidth,
              stageY >= state.outputY, stageY <= state.outputY + state.outputHeight
        else { return }
        let fx = state.cropX + ((stageX - state.outputX) / state.outputWidth) * state.cropWidth
        let fy = state.cropY + ((stageY - state.outputY) / state.outputHeight) * state.cropHeight
        changeFocus(x: fx, y: fy)
        status = "Punto d'interesse selezionato. Modifica l'intensità o scegli Zoom assistito."
    }

    func applySuggestedZoom() {
        let at = selectedTime
        let start = max(0, at - 0.45)
        let peak = at + 0.40
        let hold = at + 1.20
        let end = at + 2.20
        guard end < duration - 0.02, hold > peak, peak > start else {
            status = "Scegli un punto meno vicino alla fine del video."
            return
        }
        // Don't silently overwrite a hand-authored animation.
        guard !keyframes.contains(where: { $0.time >= start - 0.05 && $0.time <= end + 0.05 }) else {
            status = "Questa sezione contiene già uno zoom. Usa i controlli manuali oppure elimina quel keyframe."
            return
        }
        let fx = focusX, fy = focusY
        keyframes.append(contentsOf: [
            .init(time: start, zoom: 1, focusX: 0.5, focusY: 0.5),
            .init(time: peak, zoom: 1.45, focusX: fx, focusY: fy),
            .init(time: hold, zoom: 1.45, focusX: fx, focusY: fy),
            .init(time: end, zoom: 1, focusX: 0.5, focusY: 0.5)
        ])
        keyframes.sort { $0.time < $1.time }
        savePlan()
        status = "Zoom assistito creato (entrata, pausa, uscita). Puoi modificarlo manualmente."
        scrub(peak)
    }

    func removeNearestKeyframe() {
        guard let index = keyframes.indices.min(by: {
            abs(keyframes[$0].time - selectedTime) < abs(keyframes[$1].time - selectedTime)
        }), abs(keyframes[index].time - selectedTime) <= 0.40 else {
            status = "Nessun keyframe vicino al punto selezionato."
            return
        }
        keyframes.remove(at: index)
        savePlan()
        status = "Keyframe rimosso; originale invariato."
        scrub(selectedTime)
    }

    func resetCamera() {
        keyframes = []
        zoom = 1; focusX = 0.5; focusY = 0.5
        savePlan()
        status = "Zoom rimossi. La composizione originale rimane disponibile."
        refreshPreview()
    }

    func updateStyle() {
        savePlan()
        refreshPreview()
    }

    private func saveKeyframe() {
        let frame = CineoCameraKeyframe(
            time: max(0, selectedTime), zoom: zoom,
            focusX: focusX, focusY: focusY
        )
        if let existing = keyframes.firstIndex(where: { abs($0.time - frame.time) < 0.05 }) {
            keyframes[existing] = frame
        } else {
            // Without a transition keyframe, a single zoom at 15 seconds
            // would ease all the way from 0 to 15 seconds (poor demo motion).
            // Hold the prior view until 0.4s before the requested keyframe.
            let leadInTime = frame.time - 0.4
            if leadInTime > 0,
               !keyframes.contains(where: { abs($0.time - leadInTime) < 0.06 }),
               let previous = keyframes.filter({ $0.time < frame.time }).last,
               previous.time < leadInTime - 0.02 {
                keyframes.append(CineoCameraKeyframe(
                    time: leadInTime, zoom: previous.zoom,
                    focusX: previous.focusX, focusY: previous.focusY
                ))
            } else if leadInTime > 0 && keyframes.isEmpty {
                keyframes.append(CineoCameraKeyframe(
                    time: leadInTime, zoom: 1, focusX: 0.5, focusY: 0.5
                ))
            }
            keyframes.append(frame)
        }
        keyframes.sort { $0.time < $1.time }
        savePlan()
        refreshPreview()
    }

    private var planURL: URL? {
        if let projectURL { return projectURL.appendingPathComponent("scene.json") }
        guard let sourceURL else { return nil }
        let hash = SHA256.hash(data: Data(sourceURL.standardizedFileURL.path.utf8))
            .map { String(format: "%02x", $0) }.joined()
        let dir = FileManager.default.urls(for: .moviesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Cineo/Edits", isDirectory: true)
        return dir.appendingPathComponent(hash + ".json")
    }

    @discardableResult
    private func savePlan() -> Bool {
        guard let url = planURL else { return false }
        do {
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(), withIntermediateDirectories: true
            )
            let data = try JSONEncoder().encode(currentPlan)
            try data.write(to: url, options: .atomic)
            return true
        } catch {
            status = "Modifiche non salvate: \(error.localizedDescription)"
            return false
        }
    }

    private func restorePlan() {
        guard let url = planURL, FileManager.default.fileExists(atPath: url.path),
              let data = try? Data(contentsOf: url),
              let plan = try? JSONDecoder().decode(CineoScenePlan.self, from: data),
              (try? plan.validate()) != nil
        else { return }
        keyframes = plan.camera
        portrait = plan.outputHeight > plan.outputWidth
        padding = plan.paddingFraction
        if plan.background.red < 0.04 { style = "Black" }
        else if plan.background.red > 0.5 { style = "Light" }
        else { style = "Dark" }
    }

    func refreshPreview() {
        guard let url = sourceURL else { return }
        previewTask?.cancel()
        let request = UUID()
        previewRequest = request
        let plan = currentPlan
        let seconds = selectedTime
        loadingPreview = true
        previewTask = Task {
            try? await Task.sleep(for: .milliseconds(110))
            guard !Task.isCancelled else { return }
            do {
                let generator = AVAssetImageGenerator(asset: AVURLAsset(url: url))
                generator.appliesPreferredTrackTransform = true
                generator.requestedTimeToleranceBefore = CMTime(value: 1, timescale: 30)
                generator.requestedTimeToleranceAfter = CMTime(value: 1, timescale: 30)
                let cgImage = try generator.copyCGImage(
                    at: CMTime(seconds: seconds, preferredTimescale: 600), actualTime: nil
                )
                guard !Task.isCancelled, request == previewRequest else { return }
                let composited = try CineoSceneFrameRenderer.compose(
                    CIImage(cgImage: cgImage), at: seconds, with: plan
                )
                let canvas = CGRect(x: 0, y: 0,
                                    width: CGFloat(plan.outputWidth), height: CGFloat(plan.outputHeight))
                guard let rendered = CIContext().createCGImage(composited, from: canvas) else {
                    status = "Impossibile renderizzare l'anteprima."
                    return
                }
                preview = NSImage(cgImage: rendered, size: canvas.size)
                loadingPreview = false
            } catch {
                guard request == previewRequest else { return }
                status = "Anteprima non disponibile: \(error.localizedDescription)"
                loadingPreview = false
            }
        }
    }

    func export() {
        guard let url = sourceURL, !isExporting else { return }
        let plan = currentPlan
        let folder = FileManager.default.urls(for: .moviesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Cineo/Edited", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        } catch {
            status = "Impossibile preparare la destinazione: \(error.localizedDescription)"
            return
        }
        let dest = folder.appendingPathComponent(
            url.deletingPathExtension().lastPathComponent + "-edited-" +
            String(UUID().uuidString.prefix(8)).lowercased() + ".mp4"
        )
        isExporting = true
        exportProgress = 0
        outputURL = nil
        status = "Esportazione in corso: nessun file sorgente verrà modificato."
        exportTask = Task {
            do {
                try await CineoSceneExporter().export(
                    source: url, destination: dest, plan: plan
                ) { [weak self] progress in
                    Task { @MainActor [weak self] in self?.exportProgress = progress }
                }
                outputURL = dest
                status = "MP4 esportato e verificato: \(dest.lastPathComponent)"
            } catch is CancellationError {
                status = "Esportazione annullata. Il video originale è intatto."
            } catch {
                status = "Esportazione fallita, sorgente preservata: \(error.localizedDescription)"
            }
            isExporting = false
            exportTask = nil
        }
    }

    func cancelExport() {
        guard isExporting else { return }
        status = "Annullamento esportazione richiesto…"
        exportTask?.cancel()
    }

    func showExport() {
        if let outputURL { NSWorkspace.shared.activateFileViewerSelecting([outputURL]) }
    }
}

struct CineoManualEditorView: View {
    @ObservedObject var editor: CineoEditorModel
    let onClose: () -> Void

    private func control(_ getter: @escaping () -> Double,
                         _ setter: @escaping (Double) -> Void) -> Binding<Double> {
        Binding(get: getter, set: setter)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack {
                Button("‹ Registrazione") { onClose() }
                    .disabled(editor.isExporting || editor.isSavingProject)
                Text("Cineo Studio").font(.title2.bold())
                Spacer()
                Picker("Modalità", selection: Binding(
                    get: { editor.mode }, set: { editor.mode = $0 }
                )) {
                    ForEach(CineoEditorModel.Mode.allCases, id: \.self) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .frame(width: 250)
            }
            HStack {
                Text(editor.title).font(.caption).foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer()
                if editor.projectURL == nil {
                    Button("Salva progetto Cineo") { editor.saveAsProject() }
                        .disabled(editor.isSavingProject || editor.isExporting)
                } else {
                    Label("Progetto .cineo", systemImage: "checkmark.seal")
                        .foregroundStyle(.secondary)
                        .font(.caption)
                }
                if editor.isSavingProject { ProgressView().controlSize(.small) }
            }
            HStack(alignment: .top, spacing: 18) {
                VStack(spacing: 10) {
                    GeometryReader { geo in
                        let aspect = CGFloat(editor.outputWidth) / CGFloat(editor.outputHeight)
                        let w = min(geo.size.width, geo.size.height * aspect)
                        let h = w / aspect
                        VStack {
                            Spacer(minLength: 0)
                            HStack {
                                Spacer(minLength: 0)
                                Group {
                                    if let image = editor.preview {
                                        Image(nsImage: image)
                                            .resizable()
                                            .interpolation(.high)
                                            .frame(width: w, height: h)
                                            .onTapGesture { location in
                                                editor.choosePoint(
                                                    x: Double(location.x / w),
                                                    y: Double(location.y / h)
                                                )
                                            }
                                    } else {
                                        ZStack {
                                            Color.black.opacity(0.4)
                                            ProgressView("Preparazione anteprima…")
                                        }
                                        .frame(width: w, height: h)
                                    }
                                }
                                Spacer(minLength: 0)
                            }
                            Spacer(minLength: 0)
                        }
                    }
                    .frame(width: 720, height: 410)
                    HStack {
                        Text(String(format: "%02d:%05.2f",
                                    Int(editor.selectedTime) / 60,
                                    editor.selectedTime.truncatingRemainder(dividingBy: 60)))
                            .font(.caption.monospacedDigit())
                            .frame(width: 80)
                        Slider(value: control(
                            { editor.selectedTime }, { editor.scrub($0) }
                        ), in: 0...max(0.1, editor.duration - 0.05))
                        Text(String(format: "%.1f s", editor.duration))
                            .font(.caption.monospacedDigit())
                    }
                    Text("Seleziona un momento nella timeline, poi clicca sull'anteprima per scegliere il punto d'interesse.")
                        .font(.caption).foregroundStyle(.secondary)
                    if !editor.keyframes.isEmpty {
                        ScrollView(.horizontal) {
                            HStack(spacing: 6) {
                                Text("Keyframe").font(.caption.weight(.semibold))
                                ForEach(editor.keyframes, id: \.time) { key in
                                    Button(String(format: "%0.1fs · %.1f×", key.time, key.zoom)) {
                                        editor.scrub(key.time)
                                    }
                                    .buttonStyle(.bordered)
                                    .font(.caption)
                                }
                            }
                        }
                    }
                }
                VStack(alignment: .leading, spacing: 12) {
                    Text("Inquadratura").font(.headline)
                    Text(String(format: "Zoom %.2f×", editor.zoom))
                    Slider(value: control(
                        { editor.zoom }, { editor.changeZoom($0) }
                    ), in: 1...2.5)
                    Text(String(format: "Orizzontale %.0f%%", editor.focusX * 100))
                        .font(.caption)
                    Slider(value: control(
                        { editor.focusX }, { editor.changeFocus(x: $0) }
                    ), in: 0...1)
                    Text(String(format: "Verticale %.0f%%", editor.focusY * 100))
                        .font(.caption)
                    Slider(value: control(
                        { editor.focusY }, { editor.changeFocus(y: $0) }
                    ), in: 0...1)
                    HStack {
                        Button("Rimuovi keyframe") { editor.removeNearestKeyframe() }
                        Button("Reset camera") { editor.resetCamera() }
                    }
                    .font(.caption)
                    Divider()
                    Text("Composizione").font(.headline)
                    Picker("Sfondo", selection: Binding(
                        get: { editor.style },
                        set: { editor.style = $0; editor.updateStyle() }
                    )) {
                        ForEach(["Dark", "Black", "Light"], id: \.self) { name in
                            Text(name).tag(name)
                        }
                    }
                    Toggle("Formato verticale 9:16", isOn: Binding(
                        get: { editor.portrait },
                        set: { editor.portrait = $0; editor.updateStyle() }
                    ))
                    Text(String(format: "Margini %.0f%%", editor.padding * 100))
                    Slider(value: control(
                        { editor.padding },
                        { editor.padding = $0; editor.updateStyle() }
                    ), in: 0...0.25)
                    if editor.mode == .assisted {
                        Divider()
                        Text("Assistito").font(.headline)
                        Text("Seleziona un punto nell'anteprima: Cineo crea un'entrata, una pausa e un'uscita. Non analizza ancora automaticamente i click.")
                            .font(.caption).foregroundStyle(.secondary)
                        Button("Suggerisci zoom qui") { editor.applySuggestedZoom() }
                    }
                    Spacer(minLength: 0)
                    Text("\(editor.keyframes.count) keyframe salvati")
                        .font(.caption).foregroundStyle(.secondary)
                }
                .frame(width: 245, alignment: .leading)
            }
            Divider()
            HStack {
                Text(editor.status)
                    .font(.caption)
                    .textSelection(.enabled)
                    .lineLimit(2)
                Spacer()
                if editor.isExporting {
                    Button("Annulla export") { editor.cancelExport() }
                    ProgressView(value: editor.exportProgress)
                        .frame(width: 140)
                    Text("\(Int(editor.exportProgress * 100))%")
                        .monospacedDigit().font(.caption)
                }
                if editor.outputURL != nil {
                    Button("Mostra MP4") { editor.showExport() }
                }
                Button("Esporta MP4") { editor.export() }
                    .buttonStyle(.borderedProminent)
                    .disabled(editor.isExporting || editor.sourceURL == nil)
            }
        }
        .padding(20)
        .frame(minWidth: 1040, minHeight: 580)
    }
}
