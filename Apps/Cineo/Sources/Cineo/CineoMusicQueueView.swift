import SwiftUI
import CineoMusic

/// Shown in both the main video editor and Music Director. This observes the
/// application-owned queue, not the sheet lifecycle.
struct CineoMusicQueueButton: View {
    @ObservedObject var editor: CineoEditorModel
    @ObservedObject var queue: CineoMusicJobQueue
    @State private var showingQueue = false

    init(editor: CineoEditorModel) {
        self.editor = editor
        self.queue = editor.musicQueue
    }

    var body: some View {
        Button {
            showingQueue.toggle()
        } label: {
            HStack(spacing: 6) {
                if queue.activeCount > 0 { ProgressView().controlSize(.mini) }
                Image(systemName: "list.bullet.rectangle")
                Text("Coda musica")
                if queue.activeCount > 0 { Text("\(queue.activeCount)").monospacedDigit() }
                else if queue.finishedCount > 0 {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                }
            }.font(.caption)
        }
        .popover(isPresented: $showingQueue, arrowEdge: .bottom) {
            CineoMusicQueueContents(editor: editor, queue: queue)
                .frame(width: 490, height: 320)
                .padding(12)
        }
        .help("I job ACE-Step continuano mentre monti un altro video. Esito e coda persistono al riavvio.")
    }
}

struct CineoMusicQueueContents: View {
    @ObservedObject var editor: CineoEditorModel
    @ObservedObject var queue: CineoMusicJobQueue

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Coda ACE-Step locale").font(.headline)
            Text("Esecuzione seriale, non blocca l'editor. I lavori salvano l'ID remoto e possono essere ripresi quando ACE-Step resta disponibile. Non continua se chiudi completamente Cineo.")
                .font(.caption2).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Divider()
            if queue.jobs.isEmpty {
                ContentUnavailableView("Nessuna generazione in coda",
                    systemImage: "music.note",
                    description: Text("Accoda un job dal Music Director."))
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 11) {
                        ForEach(queue.jobs) { job in
                            VStack(alignment: .leading, spacing: 5) {
                                HStack(spacing: 6) {
                                    if job.phase == .running {
                                        ProgressView().controlSize(.mini)
                                    } else {
                                        Image(systemName: icon(for: job.phase))
                                            .foregroundStyle(job.phase == .ready ? .green :
                                                job.phase == .failed ? .orange : .secondary)
                                    }
                                    Text(job.kind == .generation ? "Generazione" : "Repaint")
                                        .font(.caption.weight(.semibold))
                                    Text(job.title).font(.caption).lineLimit(1)
                                    Spacer()
                                    Text(phaseText(job.phase))
                                        .font(.caption2.weight(.medium))
                                }
                                Text(job.status).font(.caption2)
                                    .foregroundStyle(.secondary).lineLimit(2)
                                HStack(spacing: 9) {
                                    if job.phase == .queued || job.phase == .running {
                                        Button("Annulla") { queue.cancel(job.id) }
                                    } else if job.phase == .ready {
                                        Button("Applica al video") { editor.applyMusicJob(job.id) }
                                            .disabled(!editor.canApplyMusicJob(job))
                                            .help(editor.canApplyMusicJob(job)
                                                ? "Applica la nuova traccia, preservando l'originale"
                                                : "Apri il video originario del job per applicarla")
                                        Button("Rimuovi dalla lista") { queue.removeRecord(job.id) }
                                    } else if job.phase == .failed || job.phase == .interrupted {
                                        Button(job.phase == .interrupted ? "Riprendi" : "Riprova") {
                                            queue.retry(job.id)
                                        }
                                        Button("Rimuovi") { queue.removeRecord(job.id) }
                                    } else {
                                        Button("Rimuovi") { queue.removeRecord(job.id) }
                                    }
                                    Spacer()
                                    Text(job.createdAt, style: .time)
                                        .font(.caption2).foregroundStyle(.tertiary)
                                }.controlSize(.mini)
                            }.padding(8)
                                .background(.quaternary.opacity(0.2),
                                            in: RoundedRectangle(cornerRadius: 8))
                        }
                    }
                }
            }
            Text("Nessun risultato viene inserito automaticamente nel montaggio. Lo stato del server può andare perso se il processo ACE-Step viene arrestato.")
                .font(.caption2).foregroundStyle(.tertiary)
        }
    }

    private func icon(for phase: CineoMusicQueueJob.Phase) -> String {
        switch phase {
        case .ready: "checkmark.circle.fill"
        case .failed: "exclamationmark.triangle"
        case .cancelled: "xmark.circle"
        case .interrupted: "arrow.clockwise.circle"
        case .running: "circle.dotted"
        case .queued: "clock"
        }
    }

    private func phaseText(_ phase: CineoMusicQueueJob.Phase) -> String {
        switch phase {
        case .queued: "In coda"
        case .running: "In esecuzione"
        case .ready: "Completato"
        case .failed: "Errore"
        case .cancelled: "Annullato"
        case .interrupted: "Interrotto"
        }
    }
}
