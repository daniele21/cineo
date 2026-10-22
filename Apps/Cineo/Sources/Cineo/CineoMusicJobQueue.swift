import Foundation
import Combine
import CineoMusic

/// One worker across all video projects. The job list is stored under the
/// user's Application Support rather than an editor view or .cineo sheet.
/// Dismissing a sheet, changing video, or closing the editor does not cancel it.
/// Explicit cancellation is the *only* normal cancellation path.
@MainActor
final class CineoMusicJobQueue: ObservableObject {
    @Published private(set) var jobs: [CineoMusicQueueJob] = []
    @Published private(set) var activeID: UUID?
    @Published private(set) var persistenceError: String?

    private let store: URL
    private let outputs: URL
    private var running: Task<Void, Never>?
    private let maxJobs = 50

    init(root: URL? = nil) {
        let dir = root ?? FileManager.default.urls(
            for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Cineo", isDirectory: true)
        self.store = dir.appendingPathComponent("music-job-queue.json")
        self.outputs = dir.appendingPathComponent("MusicJobs", isDirectory: true)
        if FileManager.default.fileExists(atPath: store.path) {
            do {
                let data = try Data(contentsOf: store)
                guard data.count < 2_000_000 else {
                    throw CineoMusicError.invalid("Cronologia di job troppo grande.")
                }
                let stored = try JSONDecoder().decode([CineoMusicQueueJob].self, from: data)
                guard stored.count <= maxJobs else {
                    throw CineoMusicError.invalid("Numero di job nella coda non valido.")
                }
                jobs = stored
                for index in jobs.indices {
                    jobs[index].recoverAfterAppRestart(
                        outputExists: FileManager.default.fileExists(
                            atPath: jobs[index].destinationPath))
                }
                save()
            } catch {
                // Never silently replace a damaged queue with an empty one.
                // Keep the original file available for manual recovery.
                persistenceError = "Impossibile leggere la coda salvata: \(error.localizedDescription). File originale preservato."
            }
        }
        Task { [weak self] in self?.pump() }
    }

    var hasWork: Bool { jobs.contains { $0.phase == .queued || $0.phase == .running } }
    var activeCount: Int { jobs.filter { $0.phase == .queued || $0.phase == .running }.count }
    var finishedCount: Int { jobs.filter { $0.phase == .ready }.count }

    func enqueueGeneration(settings: CineoMusicSettings, videoURL: URL,
                           label: String) throws {
        try enqueue(kind: .generation, settings: settings, videoURL: videoURL,
                    label: label, repaint: nil, source: nil)
    }

    func enqueueRepaint(settings: CineoMusicSettings, videoURL: URL, label: String,
                        request: CineoACERepaintRequest, audioURL: URL) throws {
        try enqueue(kind: .repaint, settings: settings, videoURL: videoURL,
                    label: label, repaint: request, source: audioURL)
    }

    private func enqueue(kind: CineoMusicQueueJob.Kind, settings: CineoMusicSettings,
                         videoURL: URL, label: String, repaint: CineoACERepaintRequest?,
                         source: URL?) throws {
        guard persistenceError == nil else {
            throw CineoMusicError.unavailable("Coda non disponibile: ripristina prima il file music-job-queue.json.")
        }
        guard videoURL.isFileURL, source == nil || source!.isFileURL else {
            throw CineoMusicError.invalid("Le sorgenti della coda devono essere file locali.")
        }
        guard jobs.filter({ $0.phase == .queued || $0.phase == .running }).count < 20 else {
            throw CineoMusicError.invalid("Coda piena (20 job attivi). Completa o annulla un job.")
        }
        let id = UUID()
        let destination = outputs.appendingPathComponent(id.uuidString + ".wav")
        let job = try CineoMusicQueueJob(id: id, kind: kind,
                     originVideoPath: videoURL.standardizedFileURL.path,
                     title: label, settings: settings, repaint: repaint,
                     sourceAudioPath: source?.standardizedFileURL.path,
                     destinationPath: destination.path)
        if jobs.count >= maxJobs {
            // Only remove finished/cancelled/failed records, never live work.
            if let idx = jobs.lastIndex(where: { $0.phase.isTerminal }) {
                jobs.remove(at: idx)
            } else {
                throw CineoMusicError.invalid("Limite cronologia coda raggiunto.")
            }
        }
        jobs.insert(job, at: 0)
        do {
            try FileManager.default.createDirectory(at: outputs, withIntermediateDirectories: true)
            try saveOrThrow()
        } catch {
            // A failed enqueue must not look queued when it never reached
            // durable storage.
            jobs.removeAll { $0.id == id }
            throw error
        }
        pump()
    }

    /// Project Save As changes the source URL; preserve the association to
    /// the same video without relaunching or cancelling remote generation.
    func relinkVideo(from old: URL, to new: URL) {
        let previous = old.standardizedFileURL.path
        let target = new.standardizedFileURL.path
        guard previous != target else { return }
        var changed = false
        for i in jobs.indices where jobs[i].originVideoPath == previous {
            jobs[i].originVideoPath = target
            changed = true
        }
        if changed { save() }
    }

    func retry(_ id: UUID) {
        guard let idx = jobs.firstIndex(where: { $0.id == id }),
              jobs[idx].phase == .interrupted || jobs[idx].phase == .failed else { return }
        // Only retain a checkpoint for interrupted transport errors; for a
        // failed server job the user must submit a fresh one deliberately.
        if jobs[idx].phase == .failed { jobs[idx].checkpoint = nil }
        jobs[idx].phase = .queued
        jobs[idx].status = jobs[idx].checkpoint == nil
            ? "Nuovo tentativo richiesto dall'utente."
            : "Ripresa del job ACE-Step esistente richiesta."
        save()
        pump()
    }

    func cancel(_ id: UUID) {
        guard let index = jobs.firstIndex(where: { $0.id == id }),
              jobs[index].phase == .queued || jobs[index].phase == .running ||
              jobs[index].phase == .interrupted else { return }
        jobs[index].phase = .cancelled
        jobs[index].status = "Annullato dall'utente. Nessuna traccia applicata."
        save()
        if activeID == id {
            running?.cancel()
        } else {
            pump()
        }
    }

    func removeRecord(_ id: UUID) {
        guard let index = jobs.firstIndex(where: { $0.id == id }),
              jobs[index].phase.isTerminal || jobs[index].phase == .interrupted else { return }
        jobs.remove(at: index)
        save()
    }

    private func pump() {
        guard persistenceError == nil, running == nil,
              let next = jobs.last(where: { $0.phase == .queued }) else { return }
        activeID = next.id
        running = Task { [weak self] in await self?.execute(next.id) }
    }

    private func execute(_ id: UUID) async {
        defer {
            running = nil
            activeID = nil
            pump()
        }
        guard let i = jobs.firstIndex(where: { $0.id == id }),
              jobs[i].phase == .queued else { return }
        jobs[i].phase = .running
        jobs[i].status = jobs[i].checkpoint == nil
            ? "Inviando il lavoro ad ACE-Step locale…"
            : "Ricollegamento al job ACE-Step già inviato…"
        save()
        let snapshot = jobs[i]
        do {
            let client = try CineoACEClient()
            let checkpoint: @Sendable (CineoACEJobCheckpoint) async throws -> Void = { [weak self] point in
                guard let self else { throw CancellationError() }
                try await self.setCheckpoint(point, for: id)
            }
            let progress: @Sendable (String) -> Void = { [weak self] message in
                Task { @MainActor [weak self] in self?.setStatus(message, for: id) }
            }
            switch snapshot.kind {
            case .generation:
                try await client.generate(
                    settings: snapshot.settings, destination: URL(fileURLWithPath: snapshot.destinationPath),
                    resumingAt: snapshot.checkpoint, onCheckpoint: checkpoint, onStatus: progress)
            case .repaint:
                guard let request = snapshot.repaint,
                      let sourcePath = snapshot.sourceAudioPath else {
                    throw CineoMusicError.invalid("Manca la sorgente del job repaint.")
                }
                try await client.repaint(request: request, source: URL(fileURLWithPath: sourcePath),
                    destination: URL(fileURLWithPath: snapshot.destinationPath),
                    resumingAt: snapshot.checkpoint, onCheckpoint: checkpoint, onStatus: progress)
            }
            guard !Task.isCancelled else { throw CancellationError() }
            if let i = jobs.firstIndex(where: { $0.id == id }),
               jobs[i].phase == .running {
                jobs[i].phase = .ready
                jobs[i].checkpoint = nil
                jobs[i].status = "Traccia pronta. Apri il video corrispondente e scegli Applica."
                save()
            }
        } catch is CancellationError {
            if let i = jobs.firstIndex(where: { $0.id == id }), jobs[i].phase == .running {
                jobs[i].phase = .cancelled
                jobs[i].status = "Generazione interrotta esplicitamente."
                save()
            }
        } catch {
            if let i = jobs.firstIndex(where: { $0.id == id }), jobs[i].phase == .running {
                let transport = String(describing: error).lowercased()
                let recoverable = jobs[i].checkpoint != nil &&
                    (transport.contains("contattare") || transport.contains("timed out") ||
                     transport.contains("connection"))
                jobs[i].phase = recoverable ? .interrupted : .failed
                jobs[i].status = "ACE-Step: \(error.localizedDescription)" +
                    (recoverable ? " Puoi riprendere il job remoto." : "")
                save()
            }
        }
    }

    private func setCheckpoint(_ point: CineoACEJobCheckpoint, for id: UUID) throws {
        guard let index = jobs.firstIndex(where: { $0.id == id }),
              jobs[index].phase == .running else { throw CancellationError() }
        let previous = jobs[index]
        jobs[index].checkpoint = point
        jobs[index].status = "ACE-Step · \(point.stage.rawValue) · job \(point.remoteID)"
        do { try saveOrThrow() }
        catch {
            jobs[index] = previous
            throw CineoMusicError.unavailable(
                "Non posso salvare il checkpoint del job sul disco: \(error.localizedDescription)")
        }
    }

    private func setStatus(_ message: String, for id: UUID) {
        guard let index = jobs.firstIndex(where: { $0.id == id }),
              jobs[index].phase == .running else { return }
        jobs[index].status = String(message.prefix(350))
        save()
    }

    private func save() {
        do { try saveOrThrow() }
        catch {
            persistenceError = "Salvataggio coda non riuscito: \(error.localizedDescription)"
            NSLog("Cineo music job queue: cannot save state: %@", error.localizedDescription)
        }
    }

    private func saveOrThrow() throws {
        try FileManager.default.createDirectory(at: store.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        let encoded = try JSONEncoder().encode(jobs)
        try encoded.write(to: store, options: .atomic)
    }
}
