import Foundation
import SwiftUI
import AVFoundation
import CoreVideo
import Combine
import AppKit
import UniformTypeIdentifiers
import CoreImage
import CineoScene
import CineoProject
import CineoMusic
import CineoAudio
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
    @Published var sourceFrameRate: Double = 30
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
    @Published private(set) var isPreviewPlaying = false
    @Published private(set) var previewActualFPS = 0
    @Published var isExporting = false
    @Published var exportProgress: Double = 0
    @Published var outputURL: URL?
    @Published var keyframes: [CineoCameraKeyframe] = []
    @Published private(set) var importedActionMarkers: [ImportedActionMarker] = []
    @Published var showingInstructions = false
    @Published var showingMusic = false
    @Published var musicSettings = CineoMusicSettings()
    @Published var musicAsset: CineoMusicAsset?
    @Published var musicDisplayName = ""
    @Published var musicActualDuration = 0.0
    @Published var musicClip = CineoMusicClip()
    @Published var duckingSettings = CineoDuckingSettings()
    @Published var musicCues: [CineoMusicCue] = []
    @Published var selectedCueKind: CineoMusicCueKind = .hit
    @Published var suggestedCueCamera: CineoCueCameraSuggestion?
    @Published var originalAudioAnalysis: CineoBeatAnalysis?
    @Published var musicAnalysis: CineoBeatAnalysis?
    @Published var suggestedBeatAlignment: CineoBeatAlignment?
    @Published var musicStatus = "Imposta la musica e avvia ACE-Step locale, oppure importa un audio."
    @Published var isGeneratingMusic = false

    struct ImportedActionMarker: Identifiable {
        let id: String
        let at: Double
    }

    private var previewTask: Task<Void, Never>?
    private var previewRequest = UUID()
    private var previewGenerator: AVAssetImageGenerator?
    private let previewCIContext = CIContext()
    private var previewPlayer: AVPlayer?
    private var previewFrameOutput: AVPlayerItemVideoOutput?
    private var displayedFrameCount = 0
    private var displayedFrameWindowStart = ProcessInfo.processInfo.systemUptime
    private var exportTask: Task<Void, Never>?
    private var musicTask: Task<Void, Never>?
    private var musicPlayer: AVPlayer?
    private var musicCrossfadePlayer: AVPlayer?
    private var originalAudioAnalysisTask: Task<Void, Never>?
    private var musicAnalysisTask: Task<Void, Never>?
    private var musicDragInitialOffset: Double?

    private struct StoredMusic: Codable {
        let settings: CineoMusicSettings
        let asset: CineoMusicAsset?
        let displayName: String?
        let clip: CineoMusicClip?
        let ducking: CineoDuckingSettings?
        let cues: [CineoMusicCue]?
    }

    private var musicDirectory: URL {
        if let projectURL { return projectURL.appendingPathComponent("Media", isDirectory: true) }
        return FileManager.default.urls(for: .moviesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Cineo/Music", isDirectory: true)
    }

    private var musicStateURL: URL? {
        if let projectURL { return projectURL.appendingPathComponent("music.json") }
        return planURL?.deletingPathExtension().appendingPathExtension("music.json")
    }

    var musicURL: URL? {
        guard let asset = musicAsset, (try? asset.validate()) != nil else { return nil }
        let url = musicDirectory.appendingPathComponent(asset.fileName)
        guard url.standardizedFileURL.deletingLastPathComponent() == musicDirectory.standardizedFileURL,
              FileManager.default.fileExists(atPath: url.path) else { return nil }
        return url
    }

    func saveMusicSettings() {
        guard let file = musicStateURL else { return }
        do {
            try musicSettings.validate(videoDuration: duration)
            try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            let stored = StoredMusic(settings: musicSettings, asset: musicAsset,
                                     displayName: musicDisplayName, clip: musicClip,
                                     ducking: duckingSettings, cues: musicCues)
            try JSONEncoder().encode(stored).write(to: file, options: .atomic)
            refreshMusicPreviewPosition()
        } catch {
            musicStatus = "Impostazioni non salvate: \(error.localizedDescription)"
        }
    }

    private func restoreMusicSettings() {
        musicPlayer?.pause()
        musicCrossfadePlayer?.pause()
        musicPlayer = nil
        musicCrossfadePlayer = nil
        musicAnalysisTask?.cancel()
        originalAudioAnalysisTask?.cancel()
        originalAudioAnalysis = nil
        musicAnalysis = nil
        suggestedBeatAlignment = nil
        musicAsset = nil
        musicDisplayName = ""
        musicActualDuration = 0
        musicClip = CineoMusicClip()
        duckingSettings = CineoDuckingSettings()
        musicCues = []
        suggestedCueCamera = nil
        musicSettings = CineoMusicSettings(duration: max(10, min(600, duration)))
        guard let file = musicStateURL,
              let data = try? Data(contentsOf: file),
              let stored = try? JSONDecoder().decode(StoredMusic.self, from: data),
              (try? stored.settings.validate(videoDuration: duration)) != nil else { return }
        musicSettings = stored.settings
        musicClip = stored.clip ?? CineoMusicClip()
        duckingSettings = stored.ducking ?? CineoDuckingSettings()
        musicCues = (stored.cues ?? []).filter { (try? $0.validate(videoDuration: duration)) != nil }
        if duckingSettings.enabled { analyzeOriginalAudioActivity() }
        if let asset = stored.asset, (try? asset.validate()) != nil {
            musicAsset = asset
            musicDisplayName = stored.displayName ?? asset.fileName
            prepareMusicPlayer()
        }
    }

    private var effectiveSourceDuration: Double {
        musicActualDuration > 0 ? musicActualDuration : max(0.01, musicSettings.duration)
    }

    var musicClipLength: Double {
        musicClip.effectiveDuration(sourceDuration: effectiveSourceDuration,
                                    videoDuration: duration, offset: musicSettings.offset)
    }

    private func prepareMusicPlayer() {
        musicPlayer?.pause()
        musicAnalysisTask?.cancel()
        musicAnalysis = nil
        suggestedBeatAlignment = nil
        musicPlayer = musicURL.map { AVPlayer(url: $0) }
        musicCrossfadePlayer = musicURL.map { AVPlayer(url: $0) }
        musicActualDuration = 0
        if let url = musicURL {
            musicAnalysisTask = Task { [weak self] in
                do {
                    let asset = AVURLAsset(url: url)
                    let length = try await asset.load(.duration)
                    guard let self, self.musicURL == url else { return }
                    if length.isNumeric { self.musicActualDuration = max(0, length.seconds) }
                    self.refreshMusicPreviewPosition()
                    let result = try await CineoMusicAudioAnalyzer.analyze(url: url)
                    try Task.checkCancellation()
                    guard self.musicURL == url else { return }
                    self.musicAnalysis = result
                    self.musicStatus = "Traccia pronta: \(result.onsets.count) accenti candidati rilevati localmente."
                } catch is CancellationError {
                    // A different track or project replaced this work.
                } catch {
                    self?.musicStatus = "Traccia caricata, ma analisi ritmica non riuscita: \(error.localizedDescription)"
                }
            }
        }
        refreshMusicPreviewPosition()
        musicStatus = musicPlayer == nil ? "Traccia musicale non disponibile." :
            "Traccia pronta per anteprima ed export. Analisi waveform in corso…"
    }

    var musicDuckingRanges: [CineoAudioActivityRange] {
        guard duckingSettings.enabled, let analysis = originalAudioAnalysis else { return [] }
        return CineoAudioActivityDetector.ranges(peakBins: analysis.activityLevels,
            duration: analysis.sourceDuration, threshold: duckingSettings.threshold)
    }

    private func analyzeOriginalAudioActivity() {
        originalAudioAnalysisTask?.cancel()
        originalAudioAnalysis = nil
        guard duckingSettings.enabled, let original = sourceURL else { return }
        musicStatus = "Analisi locale dell'attività audio originale…"
        originalAudioAnalysisTask = Task { [weak self] in
            do {
                let analysis = try await CineoMusicAudioAnalyzer.analyze(url: original)
                try Task.checkCancellation()
                guard let self, self.sourceURL == original else { return }
                self.originalAudioAnalysis = analysis
                self.musicStatus = "Ducking pronto: \(self.musicDuckingRanges.count) intervalli di attività audio."
            } catch is CancellationError {
                // Source changed or user disabled ducking.
            } catch {
                guard let self, self.sourceURL == original else { return }
                self.duckingSettings.enabled = false
                self.saveMusicSettings()
                self.musicStatus = "Ducking disattivato: l'audio originale non è analizzabile (\(error.localizedDescription))."
            }
        }
    }

    func updateDucking(enabled: Bool? = nil, level: Double? = nil,
                       threshold: Double? = nil) {
        guard !isExporting else { return }
        if let enabled { duckingSettings.enabled = enabled }
        if let level { duckingSettings.level = min(1, max(0, level)) }
        if let threshold { duckingSettings.threshold = min(1, max(0.01, threshold)) }
        if duckingSettings.enabled && originalAudioAnalysis == nil {
            analyzeOriginalAudioActivity()
        } else if !duckingSettings.enabled {
            originalAudioAnalysisTask?.cancel()
            originalAudioAnalysis = nil
        }
        saveMusicSettings()
    }

    func addMusicCue() {
        guard sourceURL != nil, !isExporting, musicCues.count < 100 else { return }
        let at = max(0, min(selectedTime, duration - 0.01))
        let cue = CineoMusicCue(at: at, kind: selectedCueKind)
        musicCues.append(cue)
        musicCues.sort { $0.at < $1.at }
        saveMusicSettings()
        musicStatus = String(format: "Cue %@ salvato a %.2f s. È un marcatore, non modifica automaticamente l'audio.",
                             selectedCueKind.rawValue, at)
    }

    func removeMusicCue(_ id: String) {
        guard !isExporting else { return }
        musicCues.removeAll { $0.id == id }
        suggestedCueCamera = nil
        saveMusicSettings()
    }

    /// Convert a manually authored cue into a camera edit only after preview
    /// and explicit confirmation; never overwrite an existing animation.
    func proposeCueCamera(_ cueID: String) {
        guard !isExporting, let cue = musicCues.first(where: { $0.id == cueID }) else {
            suggestedCueCamera = nil
            return
        }
        suggestedCueCamera = CineoCueCameraDirector.propose(
            cue: cue, videoDuration: duration,
            existing: keyframes.map { .init(time: $0.time, zoom: $0.zoom) },
            focusX: focusX, focusY: focusY)
        musicStatus = suggestedCueCamera?.description ??
            "Non posso applicare questo cue: troppo vicino al bordo oppure esistono zoom nell'intervallo."
    }

    func applyCueCamera() {
        guard !isExporting, let pending = suggestedCueCamera,
              let cue = musicCues.first(where: { $0.id == pending.cueID }),
              let rechecked = CineoCueCameraDirector.propose(
                cue: cue, videoDuration: duration,
                existing: keyframes.map { .init(time: $0.time, zoom: $0.zoom) },
                focusX: pending.frames.first(where: { $0.zoom > 1.02 })?.focusX ?? focusX,
                focusY: pending.frames.first(where: { $0.zoom > 1.02 })?.focusY ?? focusY),
              rechecked == pending else {
            musicStatus = "La proposta è cambiata: richiedi una nuova anteprima prima di applicare."
            suggestedCueCamera = nil
            return
        }
        pausePreviewPlayback()
        let original = keyframes
        keyframes.append(contentsOf: pending.frames.map {
            CineoCameraKeyframe(time: $0.time, zoom: $0.zoom,
                                focusX: $0.focusX, focusY: $0.focusY)
        })
        keyframes.sort { $0.time < $1.time }
        if savePlan() {
            importedActionMarkers = []
            suggestedCueCamera = nil
            musicStatus = "Cue applicato alla camera: " + pending.description
            scrub(cue.at)
        } else {
            keyframes = original
            suggestedCueCamera = nil
        }
    }

    /// Shared music transport: up to two simultaneous layers for genuine
    /// overlap crossfades. Any ducking/fade is identical to MP4 automation.
    private func synchronizeMusicPlayers(at videoTime: Double, seekOnly: Bool) {
        guard let first = musicPlayer else { return }
        let slots: [AVPlayer?] = [first, musicCrossfadePlayer]
        let layers = musicClip.previewLayers(videoTime: videoTime,
                            sourceDuration: effectiveSourceDuration, videoDuration: duration,
                            offset: musicSettings.offset)
        let elapsed = videoTime - musicSettings.offset
        let playable = musicClipLength
        let fadeIn = min(musicSettings.fadeIn, playable / 2)
        let fadeOut = min(musicSettings.fadeOut, playable / 2)
        let rampIn = fadeIn > 0 ? min(1, max(0, elapsed / fadeIn)) : 1
        let rampOut = fadeOut > 0 ? min(1, max(0, (playable - elapsed) / fadeOut)) : 1
        let duck = duckingSettings.gain(at: videoTime, activeRanges: musicDuckingRanges)
        for (slotIndex, player) in slots.enumerated() {
            guard let player else { continue }
            let currentLayer = layers.first { layer in
                musicClip.loop && musicClip.loopCrossfade > 0
                    ? layer.repeatIndex % 2 == slotIndex : slotIndex == 0
            }
            guard let layer = currentLayer else {
                player.pause()
                player.volume = 0
                continue
            }
            let current = player.currentTime().seconds
            if seekOnly || !current.isFinite || abs(current - layer.sourcePosition) > 0.18 {
                player.seek(to: CMTime(seconds: layer.sourcePosition,
                                      preferredTimescale: 6000),
                            toleranceBefore: .zero, toleranceAfter: .zero)
            }
            player.volume = Float(musicSettings.volume *
                         max(0, min(rampIn, rampOut)) * duck * layer.gain)
            if isPreviewPlaying && !seekOnly {
                if player.rate == 0 { player.play() }
            } else { player.pause() }
        }
    }

    private func refreshMusicPreviewPosition() {
        synchronizeMusicPlayers(at: selectedTime, seekOnly: !isPreviewPlaying)
    }

    func setMusicOffset(_ newValue: Double) {
        guard musicAsset != nil, duration > 0, !isExporting else { return }
        musicSettings.offset = min(max(0, newValue), max(0, duration - 0.01))
        suggestedBeatAlignment = nil
        saveMusicSettings()
    }

    func moveMusicByDrag(deltaX: Double, width: Double) {
        guard musicAsset != nil, width > 0, !isExporting else { return }
        if musicDragInitialOffset == nil { musicDragInitialOffset = musicSettings.offset }
        musicSettings.offset = min(max(0, musicDragInitialOffset! + deltaX / width * duration),
                                   max(0, duration - 0.01))
        suggestedBeatAlignment = nil
        refreshMusicPreviewPosition()
    }

    func endMusicDrag() {
        musicDragInitialOffset = nil
        saveMusicSettings()
    }

    func setMusicStartAtPlayhead() {
        setMusicOffset(selectedTime)
    }

    func setMusicSourceIn(_ seconds: Double) {
        guard musicAsset != nil, !isExporting else { return }
        musicClip.sourceIn = max(0, min(seconds, max(0, effectiveSourceDuration - 0.04)))
        musicClip.loopCrossfade = min(musicClip.loopCrossfade,
                                      max(0, (effectiveSourceDuration - musicClip.sourceIn) / 2))
        suggestedBeatAlignment = nil
        saveMusicSettings()
    }

    func setMusicClipDuration(_ seconds: Double) {
        guard musicAsset != nil, !isExporting else { return }
        musicClip.duration = max(0.04, min(seconds, max(0.04, duration - musicSettings.offset)))
        suggestedBeatAlignment = nil
        saveMusicSettings()
    }

    func setMusicLoop(_ enabled: Bool) {
        guard musicAsset != nil, !isExporting else { return }
        musicClip.loop = enabled
        if enabled && musicClip.duration == nil {
            musicClip.duration = max(0.04, duration - musicSettings.offset)
        }
        suggestedBeatAlignment = nil
        saveMusicSettings()
    }

    func setMusicLoopCrossfade(_ seconds: Double) {
        guard musicAsset != nil, !isExporting else { return }
        let maxAllowed = max(0, min(2, (effectiveSourceDuration - musicClip.sourceIn) / 2))
        musicClip.loopCrossfade = min(max(0, seconds), maxAllowed)
        saveMusicSettings()
    }

    /// Previewed, never applied automatically; defaults deliberately reject
    /// edits that would reorder a camera transition.
    func suggestBeatSync() {
        guard let analysis = musicAnalysis, musicAsset != nil, !keyframes.isEmpty else {
            musicStatus = "Per BeatSync servono una traccia analizzata e almeno uno zoom."
            suggestedBeatAlignment = nil
            return
        }
        let camera = keyframes.map { CineoBeatKeyframe(time: $0.time, zoom: $0.zoom) }
        suggestedBeatAlignment = CineoBeatSync.propose(
            keyframes: camera, playhead: selectedTime, onsetSeconds: analysis.onsets,
            clip: musicClip, sourceDuration: effectiveSourceDuration,
            videoDuration: duration, offset: musicSettings.offset)
        if let suggestion = suggestedBeatAlignment {
            musicStatus = String(format: "Proposta BeatSync: sposta il picco zoom da %.2f a %.2f s. Conferma per applicare.",
                                 suggestion.from, suggestion.to)
        } else {
            musicStatus = "Nessun accento entro ±0,35 s dal picco zoom selezionato, oppure modifica incompatibile con gli altri keyframe."
        }
    }

    func applyBeatSync() {
        guard let suggestion = suggestedBeatAlignment,
              keyframes.indices.contains(suggestion.keyframeIndex),
              abs(keyframes[suggestion.keyframeIndex].time - suggestion.from) < 0.001,
              !isExporting else {
            musicStatus = "Proposta BeatSync non più valida: ripeti il suggerimento."
            suggestedBeatAlignment = nil
            return
        }
        pausePreviewPlayback()
        let old = keyframes
        let frame = keyframes[suggestion.keyframeIndex]
        keyframes[suggestion.keyframeIndex] = CineoCameraKeyframe(
            time: suggestion.to, zoom: frame.zoom,
            focusX: frame.focusX, focusY: frame.focusY)
        if savePlan() {
            importedActionMarkers = []
            suggestedBeatAlignment = nil
            scrub(suggestion.to)
            musicStatus = String(format: "BeatSync applicato: picco zoom sincronizzato a %.2f s. Origine invariata.",
                                 suggestion.to)
        } else {
            keyframes = old
            suggestedBeatAlignment = nil
        }
    }

    func removeMusic() {
        guard !isExporting, !isGeneratingMusic else { return }
        musicPlayer?.pause()
        musicCrossfadePlayer?.pause()
        musicPlayer = nil
        musicCrossfadePlayer = nil
        musicAnalysisTask?.cancel()
        musicAnalysis = nil
        suggestedBeatAlignment = nil
        musicAsset = nil
        musicDisplayName = ""
        musicActualDuration = 0
        musicClip = CineoMusicClip()
        saveMusicSettings()
        musicStatus = "Traccia rimossa dal montaggio. Nessun file audio è stato cancellato."
    }

    func showMusicInFinder() {
        if let url = musicURL { NSWorkspace.shared.activateFileViewerSelecting([url]) }
    }

    func generateMusic() {
        guard sourceURL != nil, !isGeneratingMusic, !isExporting else { return }
        let settings = musicSettings
        do { try settings.validate(videoDuration: duration) }
        catch { musicStatus = error.localizedDescription; return }
        let destination = musicDirectory.appendingPathComponent(UUID().uuidString + ".wav")
        isGeneratingMusic = true
        musicStatus = "Preparazione ACE-Step…"
        musicTask = Task { [weak self] in
            guard let self else { return }
            do {
                let client = try CineoACEClient()
                try await client.generate(settings: settings, destination: destination) { message in
                    Task { @MainActor [weak self] in self?.musicStatus = message }
                }
                try Task.checkCancellation()
                self.musicAsset = CineoMusicAsset(fileName: destination.lastPathComponent, settings: settings)
                self.musicClip = CineoMusicClip()
                self.musicDisplayName = "ACE-Step · \(settings.bpm) BPM · \(Int(settings.duration)) s"
                self.prepareMusicPlayer()
                self.saveMusicSettings()
                self.musicStatus = "Traccia generata e salvata. Premi Play per ascoltarla con il video."
            } catch is CancellationError {
                try? FileManager.default.removeItem(at: destination)
                self.musicStatus = "Generazione musicale annullata."
            } catch {
                self.musicStatus = "ACE-Step: \(error.localizedDescription)"
            }
            self.isGeneratingMusic = false
            self.musicTask = nil
        }
    }

    func cancelMusicGeneration() { musicTask?.cancel() }

    func importMusicDialog() {
        guard !isExporting, !isGeneratingMusic else { return }
        let picker = NSOpenPanel()
        picker.allowedContentTypes = [.audio]
        picker.allowsMultipleSelection = false
        picker.canChooseDirectories = false
        if picker.runModal() == .OK, let url = picker.url {
            Task { await importMusic(from: url) }
        }
    }

    private func importMusic(from source: URL) async {
        guard source.isFileURL, !isExporting, !isGeneratingMusic else { return }
        do {
            let fileExt = source.pathExtension.lowercased()
            guard ["mp3", "wav", "m4a", "aiff", "aac"].contains(fileExt) else {
                throw CineoMusicError.invalid("Formato supportato: MP3, WAV, M4A, AIFF o AAC.")
            }
            let asset = AVURLAsset(url: source)
            guard !(try await asset.loadTracks(withMediaType: .audio)).isEmpty else {
                throw CineoMusicError.invalid("Il file non contiene una traccia audio.")
            }
            try FileManager.default.createDirectory(at: musicDirectory, withIntermediateDirectories: true)
            let destination = musicDirectory.appendingPathComponent(UUID().uuidString + "." + fileExt)
            try FileManager.default.copyItem(at: source, to: destination)
            musicAsset = CineoMusicAsset(fileName: destination.lastPathComponent, settings: musicSettings)
            musicClip = CineoMusicClip()
            musicDisplayName = source.lastPathComponent
            let loadedDuration = try await asset.load(.duration)
            if loadedDuration.isNumeric && loadedDuration.seconds > 0 {
                musicSettings.duration = max(10, min(600, loadedDuration.seconds))
            }
            prepareMusicPlayer()
            saveMusicSettings()
            musicStatus = "Audio importato: \(source.lastPathComponent)"
        } catch {
            musicStatus = "Importazione audio fallita: \(error.localizedDescription)"
        }
    }

    private func synchronizeMusic(at videoTime: Double) {
        synchronizeMusicPlayers(at: videoTime, seekOnly: false)
    }

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
        pausePreviewPlayback()
        musicTask?.cancel()
        musicAnalysisTask?.cancel()
        originalAudioAnalysisTask?.cancel()
        musicPlayer?.pause()
        musicCrossfadePlayer?.pause()
        musicPlayer = nil
        musicCrossfadePlayer = nil
        previewPlayer = nil
        previewFrameOutput = nil
        previewTask?.cancel()
        previewGenerator = nil
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
            let fps = Double((try? await track.load(.nominalFrameRate)) ?? 30)
            sourceFrameRate = fps.isFinite && fps > 1 && fps <= 240 ? fps : 30
            let generator = AVAssetImageGenerator(asset: asset)
            generator.appliesPreferredTrackTransform = true
            generator.requestedTimeToleranceBefore = CMTime(value: 1, timescale: 60)
            generator.requestedTimeToleranceAfter = CMTime(value: 1, timescale: 60)
            previewGenerator = generator
            // Read frames from AVPlayer's actual decoder and composite them
            // with CineoScene. Never show the raw, unedited AVPlayer surface.
            let item = AVPlayerItem(asset: asset)
            let output = AVPlayerItemVideoOutput(pixelBufferAttributes: [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
            ])
            item.add(output)
            let player = AVPlayer(playerItem: item)
            player.isMuted = false
            player.actionAtItemEnd = .pause
            previewFrameOutput = output
            previewPlayer = player
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
            importedActionMarkers = []
            title = openedProject?.title ?? url.lastPathComponent
            sourceURL = mediaURL
            projectURL = openedProject == nil ? nil : url
            restorePlan()
            restoreMusicSettings()
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
                if let originalMusic = musicURL, let musicAsset {
                    let copied = location.appendingPathComponent("Media").appendingPathComponent(musicAsset.fileName)
                    try FileManager.default.copyItem(at: originalMusic, to: copied)
                }
                projectURL = location
                sourceURL = savedSource
                if musicAsset != nil { prepareMusicPlayer() }
                if savePlan() {
                    saveMusicSettings()
                    status = "Progetto Cineo salvato: \(location.lastPathComponent)"
                }
            } catch {
                status = "Salvataggio progetto fallito: \(error.localizedDescription). Il video originale è intatto."
            }
            isSavingProject = false
        }
    }

    /// Validate the whole input before changing editor state. The final
    /// scene is evaluated by the exact same compositor used by MP4 export.
    func importInstructions(from url: URL) {
        guard sourceURL != nil, !isExporting, !isSavingProject else { return }
        do {
            let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
            let length = (attributes[.size] as? NSNumber)?.intValue ?? -1
            guard length > 0, length <= 1_048_576 else {
                throw CineoInstructionError.invalid("Il file JSON deve occupare al massimo 1 MB.")
            }
            let document = try CineoInstructionDocument.decode(
                Data(contentsOf: url, options: .mappedIfSafe)
            )
            let compiled = try document.compile(duration: duration, over: currentPlan)

            if !keyframes.isEmpty && (!document.actions.isEmpty || document.stage != nil) {
                let alert = NSAlert()
                alert.messageText = "Sostituire gli zoom attuali?"
                alert.informativeText = "Le azioni importate sostituiranno i keyframe esistenti. " +
                    "La registrazione originale non verrà modificata."
                alert.addButton(withTitle: "Importa e sostituisci")
                alert.addButton(withTitle: "Annulla")
                guard alert.runModal() == .alertFirstButtonReturn else {
                    status = "Importazione annullata; montaggio invariato."
                    return
                }
            }

            let previous = currentPlan
            keyframes = compiled.camera
            portrait = compiled.outputHeight > compiled.outputWidth
            padding = compiled.paddingFraction
            if compiled.background.red < 0.04 { style = "Black" }
            else if compiled.background.red > 0.5 { style = "Light" }
            else { style = "Dark" }

            guard savePlan() else {
                keyframes = previous.camera
                portrait = previous.outputHeight > previous.outputWidth
                padding = previous.paddingFraction
                if previous.background.red < 0.04 { style = "Black" }
                else if previous.background.red > 0.5 { style = "Light" }
                else { style = "Dark" }
                return
            }
            if let music = document.music {
                musicSettings = CineoMusicSettings(
                    caption: music.caption, bpm: music.bpm, duration: music.duration,
                    keyscale: music.keyscale, seed: music.seed,
                    volume: music.volume, offset: music.offset,
                    fadeIn: music.fadeIn, fadeOut: music.fadeOut)
                // Music changes do not silently start expensive generation.
                // Keep the existing audio until the user explicitly regenerates it.
                musicClip = CineoMusicClip(sourceIn: music.sourceIn ?? 0,
                                           duration: music.clipDuration, loop: music.loop ?? false,
                                           loopCrossfade: music.loopCrossfade ?? 0)
                duckingSettings = CineoDuckingSettings(
                    enabled: music.duckingEnabled ?? false,
                    level: music.duckingLevel ?? 0.25,
                    threshold: music.duckingThreshold ?? 0.08)
                if let importedCues = music.cues {
                    musicCues = importedCues.compactMap { cue in
                        guard let kind = CineoMusicCueKind(rawValue: cue.kind) else { return nil }
                        return CineoMusicCue(id: cue.id, at: cue.at, kind: kind, label: cue.label)
                    }
                }
                if duckingSettings.enabled { analyzeOriginalAudioActivity() }
                suggestedBeatAlignment = nil
                saveMusicSettings()
                musicStatus = "Istruzioni musicali caricate. Premi Genera per applicarle alla traccia."
            }
            importedActionMarkers = document.actions.compactMap { action in
                guard let moment = action.time ??
                    action.start.map({ $0 + (action.transition?.in ?? 0) }) else {
                    return nil
                }
                return ImportedActionMarker(id: action.id, at: moment)
            }
            let focusMoment = importedActionMarkers.first?.at ?? selectedTime
            scrub(focusMoment)
            status = "Applicate \(document.actions.count) azioni da \(url.lastPathComponent). " +
                "Sono ora keyframe modificabili, visibili nella timeline e nell'anteprima."
        } catch {
            status = "Istruzioni non applicate: \(error.localizedDescription)"
        }
    }

    func close() {
        guard !isExporting else {
            status = "Termina o annulla l'esportazione prima di chiudere l'editor."
            return
        }
        pausePreviewPlayback()
        musicTask?.cancel()
        musicPlayer = nil
        previewPlayer = nil
        previewFrameOutput = nil
        previewTask?.cancel()
        previewTask = nil
        previewGenerator = nil
        preview = nil
        sourceURL = nil
        projectURL = nil
        status = ""
    }

    func scrub(_ seconds: Double) {
        pausePreviewPlayback()
        selectedTime = min(max(seconds, 0), max(0, duration - 0.05))
        refreshMusicPreviewPosition()
        if let state = try? currentPlan.evaluate(
            time: selectedTime, sourceWidth: sourcePixelWidth, sourceHeight: sourcePixelHeight
        ) {
            zoom = 1 / state.cropWidth
            focusX = state.cropX + state.cropWidth / 2
            focusY = state.cropY + state.cropHeight / 2
        }
        refreshPreview()
    }

    /// Precise manual storyboard navigation; does not alter camera keyframes.
    func stepPreview(frames: Int) {
        guard sourceURL != nil else { return }
        scrub(selectedTime + Double(frames) / sourceFrameRate)
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
        importedActionMarkers = [] // Camera recipe has diverged from imported action labels.
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
        importedActionMarkers = []
        savePlan()
        status = "Keyframe rimosso; originale invariato."
        scrub(selectedTime)
    }

    func resetCamera() {
        keyframes = []
        importedActionMarkers = []
        zoom = 1; focusX = 0.5; focusY = 0.5
        savePlan()
        status = "Zoom rimossi. La composizione originale rimane disponibile."
        refreshPreview()
    }

    func updateStyle() {
        pausePreviewPlayback()
        savePlan()
        refreshPreview()
    }

    private func saveKeyframe() {
        pausePreviewPlayback()
        importedActionMarkers = []
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
        guard sourceURL != nil, let generator = previewGenerator else { return }
        previewTask?.cancel()
        let request = UUID()
        previewRequest = request
        let plan = currentPlan
        let seconds = selectedTime
        loadingPreview = true
        previewTask = Task {
            // A short coalescing window avoids decoding every intermediate
            // slider movement; 110 ms was too slow to judge zoom timing.
            try? await Task.sleep(for: .milliseconds(35))
            guard !Task.isCancelled else { return }
            do {
                let cgImage = try generator.copyCGImage(
                    at: CMTime(seconds: seconds, preferredTimescale: 600), actualTime: nil
                )
                guard !Task.isCancelled, request == previewRequest else { return }
                let composited = try CineoSceneFrameRenderer.compose(
                    CIImage(cgImage: cgImage), at: seconds, with: plan
                )
                let canvas = CGRect(x: 0, y: 0,
                                    width: CGFloat(plan.outputWidth), height: CGFloat(plan.outputHeight))
                guard let rendered = previewCIContext.createCGImage(composited, from: canvas) else {
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

    /// Live preview of *edited* video, using the same CineoScene frame
    /// compositor as export. AVPlayer decodes and clocks the source. The
    /// presenter drops frames when late instead of slowing the timeline.
    func togglePreviewPlayback() {
        guard let player = previewPlayer, sourceURL != nil, !isExporting else { return }
        if isPreviewPlaying {
            pausePreviewPlayback()
            status = "Anteprima in pausa. Puoi scorrere i singoli fotogrammi."
            return
        }
        if selectedTime >= duration - 0.09 {
            selectedTime = 0
        }
        previewTask?.cancel()
        previewRequest = UUID()
        let time = CMTime(seconds: selectedTime, preferredTimescale: 600)
        player.seek(to: time, toleranceBefore: .zero, toleranceAfter: .zero)
        displayedFrameCount = 0
        previewActualFPS = 0
        displayedFrameWindowStart = ProcessInfo.processInfo.systemUptime
        isPreviewPlaying = true
        loadingPreview = false
        status = "Anteprima Play: frame già composti con gli effetti Cineo, senza esportazione."
        player.play()
        synchronizeMusic(at: selectedTime)
    }

    func pausePreviewPlayback() {
        musicPlayer?.pause()
        musicCrossfadePlayer?.pause()
        guard isPreviewPlaying else { return }
        previewPlayer?.pause()
        isPreviewPlaying = false
    }

    /// Called by an active UI timer; never fabricate a playback frame. AVPlayer
    /// chooses the timeline clock; sample only if its output decoded a frame.
    func renderPlaybackTick() {
        guard isPreviewPlaying, let player = previewPlayer,
              let output = previewFrameOutput else { return }
        let timestamp = player.currentTime()
        let seconds = timestamp.seconds
        guard seconds.isFinite, seconds >= 0 else { return }
        if seconds >= duration - 0.06 {
            pausePreviewPlayback()
            selectedTime = max(0, duration - 0.06)
            status = "Anteprima terminata. L'esportazione non è necessaria per rivederla."
            return
        }
        selectedTime = seconds
        synchronizeMusic(at: seconds)
        guard output.hasNewPixelBuffer(forItemTime: timestamp),
              let buffer = output.copyPixelBuffer(forItemTime: timestamp,
                                                  itemTimeForDisplay: nil) else { return }
        do {
            let plan = currentPlan
            let stage = try CineoSceneFrameRenderer.compose(
                CIImage(cvPixelBuffer: buffer), at: seconds, with: plan
            )
            // Present a bounded ~960px proxy to reduce preview GPU load.
            // Same scene geometry and easing as final 1920/1080p export.
            let downscale = min(1.0, 960.0 / Double(max(plan.outputWidth, plan.outputHeight)))
            let scaled = stage.transformed(by: CGAffineTransform(
                scaleX: downscale, y: downscale
            ))
            let bounds = CGRect(x: 0, y: 0,
                width: CGFloat(Double(plan.outputWidth) * downscale),
                height: CGFloat(Double(plan.outputHeight) * downscale))
            if let image = previewCIContext.createCGImage(scaled, from: bounds) {
                preview = NSImage(cgImage: image, size: bounds.size)
                displayedFrameCount += 1
                let now = ProcessInfo.processInfo.systemUptime
                if now - displayedFrameWindowStart >= 1 {
                    previewActualFPS = Int((Double(displayedFrameCount) /
                        (now - displayedFrameWindowStart)).rounded())
                    displayedFrameCount = 0
                    displayedFrameWindowStart = now
                }
            }
        } catch {
            pausePreviewPlayback()
            status = "Anteprima video sospesa: \(error.localizedDescription)"
        }
    }

    func export() {
        guard let url = sourceURL, !isExporting else { return }
        pausePreviewPlayback()
        let plan = currentPlan
        // Freeze the music plan at export start; UI changes must not alter a
        // render already in progress.
        let exportMusicURL = musicURL
        let exportMusicSettings = musicSettings
        let exportMusicClip = musicClip
        let exportDucking = duckingSettings
        let exportDuckingRanges = musicDuckingRanges
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
                let videoOnly = folder.appendingPathComponent("." + UUID().uuidString + "-silent.mp4")
                defer { try? FileManager.default.removeItem(at: videoOnly) }
                try await CineoSceneExporter().export(
                    source: url, destination: videoOnly, plan: plan
                ) { [weak self] progress in
                    Task { @MainActor [weak self] in self?.exportProgress = progress * 0.85 }
                }
                let originalAsset = AVURLAsset(url: url)
                let hasOriginalAudio = !(try await originalAsset.loadTracks(withMediaType: .audio)).isEmpty
                var resolvedDuckingRanges = exportDuckingRanges
                if exportMusicURL != nil && exportDucking.enabled && hasOriginalAudio
                    && originalAudioAnalysis == nil {
                    status = "Analizzo l'attività audio originale prima del mix…"
                    let analysis = try await CineoMusicAudioAnalyzer.analyze(url: url)
                    try Task.checkCancellation()
                    resolvedDuckingRanges = CineoAudioActivityDetector.ranges(
                        peakBins: analysis.activityLevels,
                        duration: analysis.sourceDuration,
                        threshold: exportDucking.threshold)
                }
                if exportMusicURL != nil || hasOriginalAudio {
                    status = "Composizione audio/video e applicazione fade…"
                    try await CineoAudioMuxer.mux(
                        video: videoOnly, original: url,
                        music: exportMusicURL,
                        settings: exportMusicURL == nil ? nil : exportMusicSettings,
                        clip: exportMusicClip,
                        ducking: exportDucking, duckingRanges: resolvedDuckingRanges,
                        destination: dest)
                } else {
                    try FileManager.default.moveItem(at: videoOnly, to: dest)
                }
                exportProgress = 1
                outputURL = dest
                status = "MP4 con audio esportato e verificato: \(dest.lastPathComponent)"
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
                CineoBrandSymbol(size: 34)
                Text("Cineo Studio")
                    .font(CineoBrand.displayFont(size: 23))
                    .foregroundStyle(.primary) // Auto-adapts brand headline for macOS Dark Mode
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
                Button("Importa istruzioni…") {
                    let panel = NSOpenPanel()
                    panel.canChooseDirectories = false
                    panel.allowsMultipleSelection = false
                    panel.allowedContentTypes = [.json]
                    panel.message = "Seleziona un file Cineo Actions JSON v1"
                    if panel.runModal() == .OK, let url = panel.url {
                        editor.importInstructions(from: url)
                    }
                }
                .disabled(editor.isExporting || editor.isSavingProject || editor.sourceURL == nil)
                .help("Importa azioni camera.zoom, camera.keyframe e stile da JSON.")
                Button {
                    editor.showingMusic = true
                } label: {
                    Label("Musica", systemImage: "music.note")
                }
                .disabled(editor.sourceURL == nil)
                Button {
                    editor.showingInstructions = true
                } label: {
                    Label("Mostra istruzioni", systemImage: "curlybraces")
                }
                .disabled(editor.sourceURL == nil)
                .help("Vedi le istruzioni JSON equivalenti al montaggio, la guida e gli esempi.")
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
                        Button {
                            editor.togglePreviewPlayback()
                        } label: {
                            Label(editor.isPreviewPlaying ? "Pausa" : "Play",
                                  systemImage: editor.isPreviewPlaying ? "pause.fill" : "play.fill")
                        }
                        .disabled(editor.sourceURL == nil || editor.isExporting)
                        .keyboardShortcut(.space, modifiers: [])
                        .help("Riproduci gli effetti Cineo prima dell'esportazione")
                        Button { editor.stepPreview(frames: -1) } label: {
                            Image(systemName: "backward.frame.fill")
                        }
                        .help("Fotogramma precedente")
                        .disabled(editor.sourceURL == nil)
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
                        Button { editor.stepPreview(frames: 1) } label: {
                            Image(systemName: "forward.frame.fill")
                        }
                        .help("Fotogramma successivo")
                        .disabled(editor.sourceURL == nil)
                    }
                    CineoMusicTimelineStrip(editor: editor)
                    if editor.isPreviewPlaying {
                        Text("Anteprima: \(editor.previewActualFPS) fps visualizzati · qualità proxy")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                    Text("Seleziona un momento nella timeline, poi clicca sull'anteprima per scegliere il punto d'interesse.")
                        .font(.caption).foregroundStyle(.secondary)
                    if !editor.importedActionMarkers.isEmpty {
                        ScrollView(.horizontal) {
                            HStack(spacing: 6) {
                                Text("Azioni importate")
                                    .font(.caption.weight(.semibold))
                                ForEach(editor.importedActionMarkers) { action in
                                    Button(action.id) { editor.scrub(action.at) }
                                        .buttonStyle(.bordered)
                                        .font(.caption)
                                        .help(String(format: "Vai al focus a %.2f s", action.at))
                                }
                            }
                        }
                    }
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
        .tint(CineoBrand.ocean)
        .onReceive(Timer.publish(every: 1.0 / 30.0, on: .main, in: .common).autoconnect()) { _ in
            editor.renderPlaybackTick()
        }
        .sheet(isPresented: Binding(
            get: { editor.showingMusic },
            set: { editor.showingMusic = $0 }
        )) {
            CineoMusicPanel(editor: editor)
        }
        .sheet(isPresented: Binding(
            get: { editor.showingInstructions },
            set: { editor.showingInstructions = $0 }
        )) {
            CineoInstructionsDialog(editor: editor)
        }
    }
}


/// Read-only representation of the actual scene, not a speculative semantic
/// reconstruction. "Current" is regenerated from the scene each time the
/// observed editor changes; it is also importable through the existing UI.
@MainActor
private final class CineoInstructionsDialogState: ObservableObject {
    enum Tab: String, CaseIterable {
        case current = "Montaggio attuale"
        case guide = "Guida"
        case examples = "Esempi"
    }

    @Published var tab: Tab = .current
    @Published var feedback = ""
}

private struct CineoInstructionsDialog: View {
    @ObservedObject var editor: CineoEditorModel
    @Environment(\.dismiss) private var dismiss
    @StateObject private var dialog = CineoInstructionsDialogState()

    private var currentJSON: String? {
        do {
            let cameraJSON = try CineoInstructionDocument.equivalentJSON(
                for: editor.currentPlan, duration: editor.duration)
            guard var root = try JSONSerialization.jsonObject(with: Data(cameraJSON.utf8)) as? [String: Any] else {
                return nil
            }
            let m = editor.musicSettings
            let instruction = CineoInstructionDocument.Music(
                caption: m.caption, bpm: m.bpm, duration: m.duration,
                keyscale: m.keyscale, seed: m.seed, volume: m.volume,
                offset: m.offset, fadeIn: m.fadeIn, fadeOut: m.fadeOut,
                sourceIn: editor.musicClip.sourceIn,
                clipDuration: editor.musicClip.duration,
                loop: editor.musicClip.loop,
                loopCrossfade: editor.musicClip.loopCrossfade,
                duckingEnabled: editor.duckingSettings.enabled,
                duckingLevel: editor.duckingSettings.level,
                duckingThreshold: editor.duckingSettings.threshold,
                cues: editor.musicCues.map { cue in
                    CineoInstructionDocument.Music.Cue(
                        id: cue.id, at: cue.at, kind: cue.kind.rawValue, label: cue.label)
                })
            root["music"] = try JSONSerialization.jsonObject(with: JSONEncoder().encode(instruction))
            let data = try JSONSerialization.data(withJSONObject: root,
                                                  options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
            return String(decoding: data, as: UTF8.self)
        } catch { return nil }
    }

    private var generationError: String {
        do {
            _ = try CineoInstructionDocument.equivalentJSON(
                for: editor.currentPlan, duration: editor.duration
            )
            return ""
        } catch {
            return error.localizedDescription
        }
    }

    private let exampleZoom = #"""
    {
      "version": 1,
      "timebase": "output",
      "stage": {
        "aspect": "16:9",
        "background": "dark",
        "padding": 0.07
      },
      "actions": [
        {
          "id": "zoom-dashboard",
          "type": "camera.zoom",
          "start": 2.0,
          "end": 5.2,
          "target": {"x": 0.72, "y": 0.33},
          "scale": 1.7,
          "transition": {"in": 0.35, "out": 0.4}
        }
      ]
    }
    """#

    private let exampleMusic = #"""
    {
      "version": 1, "timebase": "output", "actions": [],
      "music": {
        "type": "music.generate",
        "caption": "Minimal electronic instrumental, elegant product demo, warm pads and subtle percussion",
        "bpm": 110, "duration": 45, "keyscale": "C major",
        "seed": -1, "volume": 0.4, "offset": 0,
        "fadeIn": 0.7, "fadeOut": 2.0,
        "sourceIn": 0, "clipDuration": 20, "loop": true,
        "loopCrossfade": 0.25, "duckingEnabled": false,
        "duckingLevel": 0.25, "duckingThreshold": 0.08,
        "cues": [{"id":"reveal", "at":10, "kind":"hit", "label":"Feature reveal"}]
      }
    }
    """#

    private let exampleKeyframe = #"""
    {
      "version": 1,
      "timebase": "output",
      "stage": {"aspect": "9:16", "background": "black", "padding": 0.06},
      "actions": [
        {"id": "overview", "type": "camera.keyframe", "time": 0,
         "target": {"x": 0.5, "y": 0.5}, "scale": 1},
        {"id": "focus", "type": "camera.keyframe", "time": 3,
         "target": {"x": 0.8, "y": 0.3}, "scale": 1.8},
        {"id": "restore", "type": "camera.keyframe", "time": 5,
         "target": {"x": 0.5, "y": 0.5}, "scale": 1}
      ]
    }
    """#

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Istruzioni Cineo")
                        .font(.title2.bold())
                    Text("Lo stesso montaggio, in formato JSON documentato.")
                        .foregroundStyle(.secondary)
                        .font(.callout)
                }
                Spacer()
                Button("Chiudi") { dismiss() }
            }
            Picker("Sezione", selection: $dialog.tab) {
                ForEach(CineoInstructionsDialogState.Tab.allCases, id: \.self) { option in
                    Text(option.rawValue).tag(option)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            Group {
                switch dialog.tab {
                case .current: currentContent
                case .guide: guideContent
                case .examples: examplesContent
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

            Divider()
            HStack {
                Text(dialog.feedback.isEmpty
                     ? "L'originale rimane intatto: il JSON descrive solo il montaggio."
                     : dialog.feedback)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .textSelection(.enabled)
                Spacer()
                if dialog.tab == .current, let json = currentJSON {
                    Button("Copia JSON") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(json, forType: .string)
                        dialog.feedback = "JSON del montaggio copiato."
                    }
                    Button("Salva JSON…") {
                        let panel = NSSavePanel()
                        panel.allowedContentTypes = [.json]
                        panel.nameFieldStringValue = "cineo-actions-current.json"
                        if panel.runModal() == .OK, let destination = panel.url {
                            do {
                                try Data(json.utf8).write(to: destination, options: .atomic)
                                dialog.feedback = "Istruzioni salvate: \(destination.lastPathComponent)"
                            } catch {
                                dialog.feedback = "Salvataggio fallito: \(error.localizedDescription)"
                            }
                        }
                    }
                    .buttonStyle(.borderedProminent)
                }
                if dialog.tab == .examples {
                    Button("Copia esempio zoom") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(exampleZoom, forType: .string)
                        dialog.feedback = "Esempio zoom copiato. Salvalo come .json e importalo in Studio."
                    }
                    Button("Copia esempio keyframe") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(exampleKeyframe, forType: .string)
                        dialog.feedback = "Esempio keyframe copiato. Salvalo come .json e importalo in Studio."
                    }
                    Button("Copia esempio musica") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(exampleMusic, forType: .string)
                        dialog.feedback = "Musica copiata. Importa il JSON e poi Genera con ACE-Step dalla UI."
                    }
                }
            }
        }
        .padding(20)
        .frame(width: 790, height: 630)
    }

    private var currentContent: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Queste sono le istruzioni per il video attuale e la configurazione musicale desiderata.")
                .font(.callout)
            Text("Gli zoom sono riportati come keyframe equivalenti. La sezione music descrive i parametri ACE-Step e il mix, ma non contiene il WAV: per preservare l'audio originale salva il progetto .cineo.")
                .font(.caption)
                .foregroundStyle(.secondary)
            if let json = currentJSON {
                codeArea(json)
            } else {
                ContentUnavailableView(
                    "Istruzioni non disponibili",
                    systemImage: "exclamationmark.triangle",
                    description: Text(generationError)
                )
            }
        }
    }

    private var guideContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Come leggere e scrivere le istruzioni")
                    .font(.headline)
                Text("Ogni documento contiene version, timebase, stage e actions. Puoi creare il file con un editor di testo oppure generarlo da un agente AI, poi importarlo con «Importa istruzioni…».")
                Text("**version:** 1 · **timebase:** \"output\" significa secondi sulla timeline del video.")
                Text("**stage.aspect:** \"16:9\" oppure \"9:16\". **stage.background:** \"dark\", \"black\", \"light\". **stage.padding:** fra 0 e 0.35 (escluso).")
                Text("**camera.zoom:** uno zoom completo con start, end (secondi), target x/y (coordinate da 0 a 1), scale (da 1.01 a 2.5) e transition.in/out (durata di ingresso e uscita, almeno 0.05 s). Cineo crea entrata, mantenimento e uscita.")
                Text("**camera.keyframe:** una singola inquadratura a time (secondi), target x/y (0–1) e scale (1–3). È la rappresentazione fedele delle modifiche fatte manualmente e del loro easing.")
                Text("**actions[].id:** identificativo univoco con lettere, numeri, - e _. Non puoi mescolare camera.zoom e camera.keyframe nello stesso file v1.")
                Text("Importare un file sostituisce gli zoom attuali **solo dopo tua conferma**; le impostazioni stage non specificate rimangono invariate. Effetti non implementati come cursor.highlight, text.callout e tagli vengono rifiutati.")
                Text("**music:** oggetto opzionale nello stesso JSON. type=music.generate, caption, bpm (40–240), duration (10–600 s), keyscale, seed (-1 casuale), volume (0–1), offset, fadeIn e fadeOut.")
                Text("Importare music modifica i parametri senza rigenerare automaticamente. Apri «Musica» e premi «Genera con ACE-Step». La traccia audio viene aggiunta a preview ed export.")
                Text("La preview usa lo stesso compositor video dell'export; l'audio musicale viene riprodotto con un player separato e sincronizzato sul tempo video.")
                    .foregroundStyle(.secondary)
            }
            .font(.callout)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var examplesContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("Esempio 1 — Zoom in, pausa, zoom out")
                    .font(.headline)
                Text("Un focus sul dashboard da 2.0 a 5.2 secondi. Richiede un video di almeno 5.2 secondi.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                exampleCode(exampleZoom)
                Divider()
                Text("Esempio 2 — Montaggio manuale con keyframe esatti")
                    .font(.headline)
                Text("Panoramica all'inizio, zoom a 3 s e ritorno a 5 s. Le transizioni usano lo stesso easing dell'editor.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                exampleCode(exampleKeyframe)
                Divider()
                Text("Esempio 3 — Musica ACE-Step in un documento Cineo")
                    .font(.headline)
                Text("Modifica la configurazione della musica senza perdere i keyframe esistenti. Nessun suggerimento LLM.")
                    .font(.caption).foregroundStyle(.secondary)
                exampleCode(exampleMusic)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func exampleCode(_ value: String) -> some View {
        Text(value)
            .font(.system(size: 11, design: .monospaced))
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(.quaternary.opacity(0.3), in: RoundedRectangle(cornerRadius: 8))
    }

    private func codeArea(_ value: String) -> some View {
        ScrollView([.vertical, .horizontal]) {
            exampleCode(value)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
