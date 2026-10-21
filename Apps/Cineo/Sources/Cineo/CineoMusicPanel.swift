import SwiftUI
import AppKit
import UniformTypeIdentifiers
import CineoMusic

/// The UI writes the same CineoMusicSettings used by music.generate JSON.
/// No separate prompt interpretation or LLM-based recommendations.
struct CineoMusicPanel: View {
    @ObservedObject var editor: CineoEditorModel
    @Environment(\.dismiss) private var dismiss

    private func value<T>(_ keyPath: WritableKeyPath<CineoMusicSettings, T>) -> Binding<T> {
        Binding(get: { editor.musicSettings[keyPath: keyPath] },
                set: { editor.musicSettings[keyPath: keyPath] = $0; editor.saveMusicSettings() })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Cineo Music Director", systemImage: "music.note.list").font(.title2.bold())
                Spacer()
                Button("Chiudi") { dismiss() }
            }
            Text("Controllo manuale e semi-assistito. ACE-Step genera localmente; nessun LLM suggerisce le istruzioni.")
                .foregroundStyle(.secondary).font(.caption)
            Divider()
            Text("Descrizione della musica").font(.headline)
            TextEditor(text: value(\.caption))
                .font(.body).frame(minHeight: 90, maxHeight: 110)
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(.tertiary))
            HStack {
                Text("BPM")
                Stepper(value: value(\.bpm), in: 40...240, step: 5) {
                    Text("\(editor.musicSettings.bpm)")
                        .monospacedDigit()
                }.frame(width: 105)
                Spacer()
                Text("Durata")
                TextField("secondi", value: value(\.duration), format: .number.precision(.fractionLength(0...1)))
                    .frame(width: 65)
                    .textFieldStyle(.roundedBorder)
                Button("Dal video") {
                    editor.musicSettings.duration = max(10, min(600, editor.duration))
                    editor.saveMusicSettings()
                }
            }
            HStack {
                Text("Tonalità")
                TextField("C major", text: value(\.keyscale))
                    .textFieldStyle(.roundedBorder).frame(width: 125)
                Spacer()
                Text("Seed")
                TextField("-1", value: value(\.seed), format: .number)
                    .textFieldStyle(.roundedBorder).frame(width: 120)
            }
            Divider()
            HStack {
                Text("Volume \(Int(editor.musicSettings.volume * 100))%")
                    .frame(width: 100, alignment: .leading)
                Slider(value: value(\.volume), in: 0...1)
            }
            HStack {
                Text("Offset")
                TextField("secondi", value: value(\.offset), format: .number)
                    .frame(width: 76)
                Spacer()
                Text("Fade in")
                TextField("secondi", value: value(\.fadeIn), format: .number)
                    .frame(width: 76)
                Spacer()
                Text("Fade out")
                TextField("secondi", value: value(\.fadeOut), format: .number)
                    .frame(width: 76)
            }
            .textFieldStyle(.roundedBorder)
            HStack {
                if editor.musicAsset != nil {
                    Label("Traccia presente", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                } else {
                    Label("Nessuna traccia", systemImage: "waveform")
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Importa audio…") { editor.importMusicDialog() }
                    .disabled(editor.isGeneratingMusic || editor.isExporting)
                Button(editor.isGeneratingMusic ? "Interrompi" : "Genera con ACE-Step") {
                    if editor.isGeneratingMusic { editor.cancelMusicGeneration() }
                    else { editor.generateMusic() }
                }
                .buttonStyle(.borderedProminent)
                .disabled(editor.isExporting || editor.sourceURL == nil)
            }
            if editor.isGeneratingMusic { ProgressView().controlSize(.small) }
            Text(editor.musicStatus).font(.caption).foregroundStyle(.secondary)
                .lineLimit(3).textSelection(.enabled)
            Text("ACE-Step server locale: http://127.0.0.1:8080. Configura i modelli GGUF e avvia ace-server. La generazione produce WAV 48 kHz da aggiungere al progetto.")
                .font(.caption2).foregroundStyle(.tertiary)
        }
        .padding(20)
        .frame(width: 690, height: 580)
    }
}
