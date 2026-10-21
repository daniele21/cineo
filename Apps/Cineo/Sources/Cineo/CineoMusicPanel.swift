import SwiftUI
import AppKit
import UniformTypeIdentifiers
import CineoMusic

/// Visual clip overlay on the *same output-time timeline* as the camera.
struct CineoMusicTimelineStrip: View {
    @ObservedObject var editor: CineoEditorModel

    var body: some View {
        if editor.musicAsset != nil {
            HStack(spacing: 10) {
                Image(systemName: "waveform")
                    .foregroundStyle(CineoBrand.ocean)
                    .frame(width: 20)
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(editor.musicDisplayName.isEmpty ? "Traccia musicale" : editor.musicDisplayName)
                            .font(.caption.weight(.semibold))
                            .lineLimit(1)
                        Spacer()
                        Text(String(format: "Inizio %.2f s", editor.musicSettings.offset))
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                    GeometryReader { geo in
                        let width = max(1, geo.size.width)
                        let total = max(0.1, editor.duration)
                        let offset = min(total, max(0, editor.musicSettings.offset))
                        let audioLength = editor.musicActualDuration > 0
                            ? editor.musicActualDuration : editor.musicSettings.duration
                        let length = min(editor.musicSettings.duration, audioLength,
                                         max(0, total - offset))
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 5)
                                .fill(.secondary.opacity(0.12))
                            RoundedRectangle(cornerRadius: 5)
                                .fill(CineoBrand.ocean.opacity(0.52))
                                .frame(width: max(0, length / total * width))
                                .offset(x: offset / total * width)
                            Rectangle()
                                .fill(.primary.opacity(0.85))
                                .frame(width: 2)
                                .offset(x: min(width - 2, editor.selectedTime / total * width))
                        }
                        .contentShape(Rectangle())
                        .gesture(DragGesture(minimumDistance: 0)
                            .onChanged { gesture in
                                editor.setMusicOffset((gesture.location.x / width) * total)
                            })
                    }
                    .frame(height: 22)
                    .help("Trascina per spostare l'inizio della musica sulla timeline del video.")
                }
                Button {
                    editor.showingMusic = true
                } label: {
                    Image(systemName: "slider.horizontal.3")
                }
                .help("Modifica traccia musicale")
            }
            .padding(.vertical, 5)
        }
    }
}

/// The audio clip and settings are a single source of truth, also edited
/// through the strict music.generate JSON. No second timeline or LLM.
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

    private var playableDuration: Double {
        let source = editor.musicActualDuration > 0 ? editor.musicActualDuration : editor.musicSettings.duration
        return max(0, min(source, editor.musicSettings.duration,
                          editor.duration - editor.musicSettings.offset))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Music Director", systemImage: "music.note.list")
                    .font(.title2.bold())
                Spacer()
                Button("Chiudi") { dismiss() }
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 13) {
                    if editor.musicAsset != nil {
                        trackSection
                        Divider()
                    }
                    Text("Genera musica locale con ACE-Step")
                        .font(.headline)
                    Text("Descrivi genere, strumenti e atmosfera. Cineo non suggerisce istruzioni tramite LLM.")
                        .font(.caption).foregroundStyle(.secondary)
                    TextEditor(text: value(\.caption))
                        .font(.body)
                        .frame(minHeight: 64, maxHeight: 85)
                        .overlay(RoundedRectangle(cornerRadius: 7).stroke(.tertiary))
                    HStack {
                        Text("BPM")
                        Stepper(value: value(\.bpm), in: 40...240, step: 5) {
                            Text("\(editor.musicSettings.bpm)")
                                .monospacedDigit()
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
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(editor.isExporting || editor.sourceURL == nil)
                        Spacer()
                    }
                    if editor.isGeneratingMusic {
                        ProgressView().controlSize(.small)
                        Text("Il motore comunica la fase, non la percentuale di avanzamento.")
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                    Text(editor.musicStatus)
                        .font(.caption).foregroundStyle(.secondary)
                        .textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                    Text("Backend locale: http://127.0.0.1:8080. ACE-Step deve essere installato e avviato separatamente.")
                        .font(.caption2).foregroundStyle(.tertiary)
                }
            }
        }
        .padding(20)
        .frame(width: 720, height: 660)
    }

    private var trackSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 10) {
                Image(systemName: "waveform")
                    .foregroundStyle(CineoBrand.ocean)
                VStack(alignment: .leading, spacing: 2) {
                    Text(editor.musicDisplayName.isEmpty ? "Traccia importata" : editor.musicDisplayName)
                        .font(.headline).lineLimit(1)
                    Text(String(format: "Audio %.1f s · Usati %.1f s · Inizio %.2f s",
                        editor.musicActualDuration, playableDuration, editor.musicSettings.offset))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button {
                    editor.showMusicInFinder()
                } label: { Image(systemName: "folder") }
                .help("Mostra il file audio in Finder")
                Button(role: .destructive) { editor.removeMusic() } label: {
                    Label("Rimuovi", systemImage: "trash")
                }
                .disabled(editor.isGeneratingMusic || editor.isExporting)
            }
            CineoMusicTimelineStrip(editor: editor)
            HStack {
                Text("Posizione")
                    .frame(width: 78, alignment: .leading)
                Slider(value: offsetBinding,
                       in: 0...max(0.01, editor.duration - 0.01))
                Text(String(format: "%.2f s", editor.musicSettings.offset))
                    .monospacedDigit().frame(width: 65)
                Button("Inizia qui") { editor.setMusicStartAtPlayhead() }
                    .help("Sposta l'inizio musicale al punto corrente del video")
            }
            HStack {
                Text("Volume")
                    .frame(width: 78, alignment: .leading)
                Slider(value: value(\.volume), in: 0...1)
                Text("\(Int(editor.musicSettings.volume * 100))%")
                    .monospacedDigit().frame(width: 65)
                Button(editor.isPreviewPlaying ? "Pausa" : "Play") {
                    editor.togglePreviewPlayback()
                }
                .disabled(editor.isExporting)
            }
            HStack {
                Text("Fade in")
                TextField("secondi", value: value(\.fadeIn),
                          format: .number.precision(.fractionLength(0...1)))
                    .frame(width: 65)
                Text("Fade out")
                TextField("secondi", value: value(\.fadeOut),
                          format: .number.precision(.fractionLength(0...1)))
                    .frame(width: 65)
                Spacer()
                Text("La musica non modifica i click e gli zoom.")
                    .font(.caption2).foregroundStyle(.secondary)
            }
            .textFieldStyle(.roundedBorder)
        }
    }
}
