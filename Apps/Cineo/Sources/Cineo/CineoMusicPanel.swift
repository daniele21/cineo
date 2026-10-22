import SwiftUI
import AppKit
import UniformTypeIdentifiers
import CineoMusic

/// Source-relative waveform, onsets, clip duration and camera playhead share
/// the one Cineo output-time axis. Audio is never edited destructively.
struct CineoMusicTimelineStrip: View {
    @ObservedObject var editor: CineoEditorModel

    var body: some View {
        if editor.musicAsset != nil {
            HStack(spacing: 10) {
                Image(systemName: "waveform").foregroundStyle(CineoBrand.ocean).frame(width: 20)
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(editor.musicDisplayName.isEmpty ? "Traccia musicale" : editor.musicDisplayName)
                            .font(.caption.weight(.semibold)).lineLimit(1)
                        Spacer()
                        Text(String(format: "Inizio %.2f s · durata %.1f s",
                                    editor.musicSettings.offset, editor.musicClipLength))
                            .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                    }
                    GeometryReader { geo in
                        Canvas { context, size in
                            let total = max(0.1, editor.duration)
                            let offset = editor.musicSettings.offset
                            let length = editor.musicClipLength
                            let startX = size.width * CGFloat(offset / total)
                            let clipWidth = max(0, size.width * CGFloat(length / total))
                            let background = CGRect(x: 0, y: 0, width: size.width, height: size.height)
                            context.fill(Path(roundedRect: background, cornerRadius: 5),
                                         with: .color(.secondary.opacity(0.12)))
                            let clipRect = CGRect(x: startX, y: 0,
                                                  width: clipWidth, height: size.height)
                            context.fill(Path(roundedRect: clipRect, cornerRadius: 4),
                                         with: .color(CineoBrand.ocean.opacity(0.25)))
                            if let analysis = editor.musicAnalysis, analysis.sourceDuration > 0,
                               let segments = try? editor.musicClip.segments(
                                    sourceDuration: editor.musicActualDuration > 0
                                        ? editor.musicActualDuration : analysis.sourceDuration,
                                    videoDuration: editor.duration, offset: offset) {
                                var waves = Path()
                                for segment in segments {
                                    for (index, amplitude) in analysis.waveform.enumerated() {
                                        let sourceTime = (Double(index) + 0.5) /
                                                         Double(analysis.waveform.count) * analysis.sourceDuration
                                        guard sourceTime >= segment.sourceStart,
                                              sourceTime < segment.sourceStart + segment.duration else { continue }
                                        let videoTime = segment.timelineStart + sourceTime - segment.sourceStart
                                        let x = size.width * CGFloat(videoTime / total)
                                        let h = max(1.5, CGFloat(amplitude) * size.height * 0.45)
                                        waves.move(to: CGPoint(x: x, y: size.height / 2 - h))
                                        waves.addLine(to: CGPoint(x: x, y: size.height / 2 + h))
                                    }
                                }
                                context.stroke(waves, with: .color(CineoBrand.ocean), lineWidth: 1.25)
                                var accents = Path()
                                for segment in segments {
                                    for onset in analysis.onsets {
                                        guard onset >= segment.sourceStart,
                                              onset < segment.sourceStart + segment.duration else { continue }
                                        let x = size.width * CGFloat((segment.timelineStart + onset - segment.sourceStart) / total)
                                        accents.move(to: CGPoint(x: x, y: 0))
                                        accents.addLine(to: CGPoint(x: x, y: size.height))
                                    }
                                }
                                context.stroke(accents, with: .color(.orange.opacity(0.85)), lineWidth: 1)
                            }
                            var cues = Path()
                            for cue in editor.musicCues {
                                let x = size.width * CGFloat(cue.at / total)
                                cues.move(to: CGPoint(x: x, y: 0))
                                cues.addLine(to: CGPoint(x: x, y: size.height))
                            }
                            context.stroke(cues, with: .color(.purple.opacity(0.85)), lineWidth: 2)
                            let playheadX = max(0, min(size.width - 2,
                                size.width * CGFloat(editor.selectedTime / total)))
                            var playhead = Path()
                            playhead.move(to: CGPoint(x: playheadX, y: 0))
                            playhead.addLine(to: CGPoint(x: playheadX, y: size.height))
                            context.stroke(playhead, with: .color(.primary), lineWidth: 2)
                        }
                        .contentShape(Rectangle())
                        .gesture(DragGesture(minimumDistance: 4)
                            .onChanged { gesture in
                                editor.moveMusicByDrag(deltaX: Double(gesture.translation.width),
                                                       width: Double(geo.size.width))
                            }.onEnded { _ in editor.endMusicDrag() })
                        .help("Trascina per spostare la traccia senza cambiare il tempo della sorgente.")
                    }
                    .frame(height: 28)
                }
                Button { editor.showingMusic = true } label: {
                    Image(systemName: "slider.horizontal.3")
                }.help("Modifica traccia musicale")
            }
            .padding(.vertical, 5)
        }
    }
}

/// Manual Music Director + optional deterministic BeatSync suggestions.
struct CineoMusicPanel: View {
    @ObservedObject var editor: CineoEditorModel
    @Environment(\.dismiss) private var dismiss

    private func value<T>(_ keyPath: WritableKeyPath<CineoMusicSettings, T>) -> Binding<T> {
        Binding(get: { editor.musicSettings[keyPath: keyPath] },
                set: { editor.musicSettings[keyPath: keyPath] = $0; editor.saveMusicSettings() })
    }

    private var offsetBinding: Binding<Double> {
        Binding(get: { editor.musicSettings.offset }, set: { editor.setMusicOffset($0) })
    }

    private var sourceInBinding: Binding<Double> {
        Binding(get: { editor.musicClip.sourceIn }, set: { editor.setMusicSourceIn($0) })
    }

    private var durationBinding: Binding<Double> {
        Binding(get: { editor.musicClip.duration ?? max(0.04, editor.musicClipLength) },
                set: { editor.setMusicClipDuration($0) })
    }

    private var loopBinding: Binding<Bool> {
        Binding(get: { editor.musicClip.loop }, set: { editor.setMusicLoop($0) })
    }

    private var crossfadeBinding: Binding<Double> {
        Binding(get: { editor.musicClip.loopCrossfade },
                set: { editor.setMusicLoopCrossfade($0) })
    }

    private var duckEnabledBinding: Binding<Bool> {
        Binding(get: { editor.duckingSettings.enabled },
                set: { editor.updateDucking(enabled: $0) })
    }

    private var duckLevelBinding: Binding<Double> {
        Binding(get: { editor.duckingSettings.level },
                set: { editor.updateDucking(level: $0) })
    }

    private var duckThresholdBinding: Binding<Double> {
        Binding(get: { editor.duckingSettings.threshold },
                set: { editor.updateDucking(threshold: $0) })
    }

    private var cueKindBinding: Binding<CineoMusicCueKind> {
        Binding(get: { editor.selectedCueKind },
                set: { editor.selectedCueKind = $0 })
    }

    private var maxPlayLength: Double {
        let byVideo = max(0.04, editor.duration - editor.musicSettings.offset)
        if editor.musicClip.loop { return byVideo }
        return max(0.04, min(byVideo,
            editor.musicActualDuration - editor.musicClip.sourceIn))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Music Director", systemImage: "music.note.list").font(.title2.bold())
                Spacer()
                Button("Chiudi") { dismiss() }
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 13) {
                    if editor.musicAsset != nil {
                        trackSection
                        Divider()
                    }
                    Text("Genera musica locale con ACE-Step").font(.headline)
                    Text("Descrivi genere, strumenti e atmosfera. I suggerimenti LLM restano disattivati.")
                        .font(.caption).foregroundStyle(.secondary)
                    TextEditor(text: value(\.caption))
                        .font(.body).frame(minHeight: 64, maxHeight: 85)
                        .overlay(RoundedRectangle(cornerRadius: 7).stroke(.tertiary))
                    HStack {
                        Text("BPM")
                        Stepper(value: value(\.bpm), in: 40...240, step: 5) {
                            Text("\(editor.musicSettings.bpm)").monospacedDigit()
                        }.frame(width: 110)
                        Spacer()
                        Text("Durata generazione")
                        TextField("secondi", value: value(\.duration),
                                  format: .number.precision(.fractionLength(0...1)))
                            .frame(width: 64).textFieldStyle(.roundedBorder)
                        Button("Dal video") {
                            editor.musicSettings.duration = max(10, min(600, editor.duration))
                            editor.saveMusicSettings()
                        }
                    }
                    HStack {
                        Text("Tonalità")
                        TextField("C major", text: value(\.keyscale))
                            .textFieldStyle(.roundedBorder).frame(width: 120)
                        Spacer()
                        Text("Seed")
                        TextField("-1", value: value(\.seed), format: .number)
                            .textFieldStyle(.roundedBorder).frame(width: 105)
                    }
                    HStack(spacing: 12) {
                        Button("Importa / sostituisci audio…") { editor.importMusicDialog() }
                            .disabled(editor.isGeneratingMusic || editor.isExporting)
                        Button(editor.isGeneratingMusic ? "Annulla generazione" : "Genera con ACE-Step") {
                            if editor.isGeneratingMusic { editor.cancelMusicGeneration() }
                            else { editor.generateMusic() }
                        }.buttonStyle(.borderedProminent)
                            .disabled(editor.isExporting || editor.sourceURL == nil)
                        Spacer()
                    }
                    if editor.isGeneratingMusic {
                        ProgressView().controlSize(.small)
                        Text("ACE-Step restituisce la fase, non una percentuale reale.")
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                    Text(editor.musicStatus).font(.caption).foregroundStyle(.secondary)
                        .textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                    Text("Backend locale: http://127.0.0.1:8080. Nessun accesso cloud necessario.")
                        .font(.caption2).foregroundStyle(.tertiary)
                }
            }
        }
        .padding(20).frame(width: 720, height: 710)
    }

    private var trackSection: some View {
        VStack(alignment: .leading, spacing: 11) {
            HStack(spacing: 10) {
                Image(systemName: "waveform").foregroundStyle(CineoBrand.ocean)
                VStack(alignment: .leading, spacing: 2) {
                    Text(editor.musicDisplayName.isEmpty ? "Traccia importata" : editor.musicDisplayName)
                        .font(.headline).lineLimit(1)
                    Text(String(format: "Sorgente %.1f s · In video %.1f s",
                        editor.musicActualDuration, editor.musicClipLength))
                        .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                }
                Spacer()
                Button { editor.showMusicInFinder() } label: { Image(systemName: "folder") }
                    .help("Mostra audio in Finder")
                Button(role: .destructive) { editor.removeMusic() } label: {
                    Label("Rimuovi", systemImage: "trash")
                }.disabled(editor.isGeneratingMusic || editor.isExporting)
            }
            CineoMusicTimelineStrip(editor: editor)
            HStack {
                Text("Inizio nel video").frame(width: 105, alignment: .leading)
                Slider(value: offsetBinding, in: 0...max(0.01, editor.duration - 0.01))
                Text(String(format: "%.2f s", editor.musicSettings.offset))
                    .monospacedDigit().frame(width: 60)
                Button("Inizia qui") { editor.setMusicStartAtPlayhead() }
            }
            HStack {
                Text("Taglio sorgente").frame(width: 105, alignment: .leading)
                Slider(value: sourceInBinding,
                       in: 0...max(0.001, editor.musicActualDuration - 0.05))
                Text(String(format: "%.2f s", editor.musicClip.sourceIn))
                    .monospacedDigit().frame(width: 60)
            }
            HStack {
                Text("Durata nel video").frame(width: 105, alignment: .leading)
                Slider(value: durationBinding, in: 0.04...max(0.05, maxPlayLength))
                Text(String(format: "%.2f s", editor.musicClipLength))
                    .monospacedDigit().frame(width: 60)
                Button("Auto") {
                    editor.musicClip.duration = nil
                    editor.saveMusicSettings()
                }.help("Usa tutto l'audio disponibile (o tutto il video se Loop è attivo)")
            }
            Toggle("Ripeti la traccia (loop)", isOn: loopBinding)
                .disabled(editor.isExporting)
            if editor.musicClip.loop {
                HStack {
                    Text("Crossfade loop").frame(width: 105, alignment: .leading)
                    Slider(value: crossfadeBinding, in: 0...max(0.001,
                        min(2, (editor.musicActualDuration - editor.musicClip.sourceIn) / 2)))
                    Text(String(format: "%.2f s", editor.musicClip.loopCrossfade))
                        .font(.caption.monospacedDigit()).frame(width: 60)
                }
                Text("Sovrappone due ripetizioni e sfuma l'una nell'altra (0 = taglio netto).")
                    .font(.caption2).foregroundStyle(.secondary)
            }
            HStack {
                Text("Volume").frame(width: 105, alignment: .leading)
                Slider(value: value(\.volume), in: 0...1)
                Text("\(Int(editor.musicSettings.volume * 100))%")
                    .monospacedDigit().frame(width: 60)
                Button(editor.isPreviewPlaying ? "Pausa" : "Play") {
                    editor.togglePreviewPlayback()
                }.disabled(editor.isExporting)
            }
            HStack {
                Text("Fade in")
                TextField("secondi", value: value(\.fadeIn),
                          format: .number.precision(.fractionLength(0...1)))
                    .frame(width: 70)
                Text("Fade out")
                TextField("secondi", value: value(\.fadeOut),
                          format: .number.precision(.fractionLength(0...1)))
                    .frame(width: 70)
                Spacer()
            }.textFieldStyle(.roundedBorder)
            Divider()
            Toggle("Ducking durante l'audio originale", isOn: duckEnabledBinding)
                .disabled(editor.isExporting)
            if editor.duckingSettings.enabled {
                HStack {
                    Text("Volume musica").frame(width: 105, alignment: .leading)
                    Slider(value: duckLevelBinding, in: 0...1)
                    Text("\(Int(editor.duckingSettings.level * 100))%")
                        .font(.caption.monospacedDigit()).frame(width: 60)
                }
                HStack {
                    Text("Soglia attività").frame(width: 105, alignment: .leading)
                    Slider(value: duckThresholdBinding, in: 0.01...0.5)
                    Text(String(format: "%.2f", editor.duckingSettings.threshold))
                        .font(.caption.monospacedDigit()).frame(width: 60)
                }
                Text("\(editor.musicDuckingRanges.count) intervalli attivi. Analisi di volume, non riconoscimento della voce: anche i suoni di sistema possono attivare il ducking.")
                    .font(.caption2).foregroundStyle(.secondary)
            }
            Divider()
            Text("Cue musicali manuali").font(.headline)
            HStack {
                Picker("Tipo", selection: cueKindBinding) {
                    Text("Hit").tag(CineoMusicCueKind.hit)
                    Text("Crescendo").tag(CineoMusicCueKind.crescendo)
                    Text("Transizione").tag(CineoMusicCueKind.transition)
                }.frame(width: 230)
                Button("Aggiungi al playhead") { editor.addMusicCue() }
                    .disabled(editor.musicCues.count >= 100 || editor.isExporting)
                Spacer()
            }
            if !editor.musicCues.isEmpty {
                ScrollView(.horizontal) {
                    HStack(spacing: 8) {
                        ForEach(editor.musicCues) { cue in
                            Button(String(format: "%@ %.2f s", cue.kind.rawValue, cue.at)) {
                                editor.scrub(cue.at)
                            }
                            Button { editor.removeMusicCue(cue.id) } label: {
                                Image(systemName: "xmark.circle")
                            }.help("Elimina cue")
                        }
                    }.font(.caption)
                }
            }
            Text("I cue sono marcatori modificabili, non effetti sonori generati automaticamente.")
                .font(.caption2).foregroundStyle(.secondary)
            Divider()
            HStack {
                Text("BeatSync").font(.headline)
                Spacer()
                if let analysis = editor.musicAnalysis {
                    Text("\(analysis.onsets.count) accenti rilevati")
                        .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                } else {
                    ProgressView().controlSize(.small)
                    Text("Analisi locale…").font(.caption).foregroundStyle(.secondary)
                }
            }
            Text("Seleziona sulla timeline il picco di uno zoom. Cineo cerca un accento reale entro ±0,35 s e propone uno spostamento. Non modifica altri keyframe.")
                .font(.caption).foregroundStyle(.secondary)
            HStack {
                Button("Suggerisci allineamento") { editor.suggestBeatSync() }
                    .disabled(editor.musicAnalysis == nil || editor.isExporting)
                if let proposal = editor.suggestedBeatAlignment {
                    Text(String(format: "%.2f → %.2f s", proposal.from, proposal.to))
                        .font(.caption.monospacedDigit())
                    Button("Applica BeatSync") { editor.applyBeatSync() }
                        .buttonStyle(.borderedProminent)
                    Button("Annulla") { editor.suggestedBeatAlignment = nil }
                }
                Spacer()
            }
        }
    }
}
