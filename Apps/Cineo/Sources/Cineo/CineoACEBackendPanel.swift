import SwiftUI
import AppKit
import CineoMusic

/// On-device server controls. Explicit user action for any process launch;
/// model downloads and compiler tools are never invoked automatically.
struct CineoACEBackendPanel: View {
    @ObservedObject var backend: CineoACEBackendController

    private var statusIcon: String {
        switch backend.phase {
        case .ready: "checkmark.circle.fill"
        case .launching, .checking: "arrow.triangle.2.circlepath"
        case .missing, .failed: "exclamationmark.triangle.fill"
        case .stopped: "circle.dotted"
        }
    }

    private var statusColor: Color {
        switch backend.phase {
        case .ready: .green
        case .missing, .failed: .orange
        default: .secondary
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 8) {
                Label("Motore ACE-Step locale", systemImage: "server.rack")
                    .font(.headline)
                Spacer()
                Image(systemName: statusIcon).foregroundStyle(statusColor)
                Text(backend.phase == .ready ? "Pronto" :
                     backend.phase == .launching ? "Avvio" :
                     backend.phase == .checking ? "Verifica" :
                     backend.phase == .missing ? "Non configurato" :
                     backend.phase == .failed ? "Errore" : "Fermo")
                    .font(.caption.weight(.medium))
            }
            Text(backend.detail).font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if let root = backend.selectedRoot {
                Text(root.path).font(.caption.monospaced())
                    .foregroundStyle(.secondary).lineLimit(2)
                    .textSelection(.enabled)
            }
            HStack(spacing: 8) {
                Button("Scegli cartella…") { backend.chooseFolder() }
                    .disabled(backend.isBusy || backend.isManaged || backend.downloader.isDownloading)
                Button("Verifica") {
                    Task { await backend.refresh() }
                }.disabled(backend.isBusy)
                Button("Avvia motore") { backend.start() }
                    .disabled(backend.isBusy || backend.isReady || backend.selectedRoot == nil || backend.downloader.isDownloading)
                if backend.isManaged {
                    Button("Arresta") { backend.stop() }
                }
                Spacer()
                if backend.selectedRoot != nil {
                    Button("Apri modelli") { backend.revealModels() }
                }
            }.controlSize(.small)

            if backend.phase != .ready {
                let missing = backend.missingModels
                if !missing.isEmpty {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("GGUF mancanti o incompleti").font(.caption.weight(.semibold))
                        ForEach(missing, id: \.self) { file in
                            Label(file, systemImage: "exclamationmark.circle")
                                .font(.caption2.monospaced()).foregroundStyle(.secondary)
                        }
                        CineoACEModelDownloadControls(backend: backend,
                                                      downloader: backend.downloader)
                        Text("Alternativa da Terminale: ./models.sh. I file GGUF vengono conservati nella cartella ACE-Step.")
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                }
            }
            if backend.isBusy {
                ProgressView().controlSize(.small)
                Text("Stato di avvio, non percentuale di generazione musicale.")
                    .font(.caption2).foregroundStyle(.tertiary)
            }
            if !backend.recentLog.isEmpty {
                DisclosureGroup("Log locali del server") {
                    ScrollView {
                        Text(backend.recentLog).font(.caption2.monospaced())
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(height: 105)
                }
                .font(.caption)
            }
            Text("Porta 8080 · solo 127.0.0.1 · i server avviati esternamente non vengono arrestati da Cineo.")
                .font(.caption2).foregroundStyle(.tertiary)
        }
        .padding(12)
        .background(.quaternary.opacity(0.24), in: RoundedRectangle(cornerRadius: 10))
        .task { await backend.refresh() }
    }
}


/// User must explicitly confirm the multi-gigabyte model download.
/// No shells or arbitrary remote URLs: hf is run with fixed arguments.
private struct CineoACEModelDownloadControls: View {
    @ObservedObject var backend: CineoACEBackendController
    @ObservedObject var downloader: CineoACEModelDownloader

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                if downloader.isDownloading {
                    Button("Annulla download") { downloader.cancel() }
                    Text("\(downloader.completedFiles)/\(downloader.totalFiles) file completati")
                        .font(.caption2.monospacedDigit())
                } else {
                    Button("Scarica GGUF mancanti…") {
                        guard let installation = backend.installation else { return }
                        let missing = installation.unavailableModels()
                        guard !missing.isEmpty else { return }
                        let alert = NSAlert()
                        alert.messageText = "Scaricare i modelli ACE-Step?"
                        alert.informativeText = "Scaricherai \(missing.count) file GGUF dal repository Hugging Face Serveurperso/ACE-Step-1.5-GGUF. " +
                            "Il download completo richiede circa 7,7 GB, più spazio temporaneo. " +
                            "Le richieste partono solo dopo la tua conferma."
                        alert.addButton(withTitle: "Scarica")
                        alert.addButton(withTitle: "Annulla")
                        guard alert.runModal() == .alertFirstButtonReturn else { return }
                        downloader.downloadMissing(installation: installation) {
                            Task { await backend.refresh() }
                        }
                    }
                    .disabled(backend.isBusy || backend.isManaged)
                }
                Spacer()
            }
            if !downloader.status.isEmpty {
                Text(downloader.status).font(.caption2)
                    .foregroundStyle(.secondary).textSelection(.enabled)
            }
            if downloader.isDownloading {
                ProgressView(value: Double(downloader.completedFiles),
                             total: Double(max(1, downloader.totalFiles)))
                    .help("Mostra solo file completati, non la percentuale del file in download.")
            }
            if !downloader.log.isEmpty {
                DisclosureGroup("Log del download") {
                    ScrollView {
                        Text(downloader.log)
                            .font(.caption2.monospaced())
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .textSelection(.enabled)
                    }.frame(height: 80)
                }.font(.caption)
            }
        }
    }
}
