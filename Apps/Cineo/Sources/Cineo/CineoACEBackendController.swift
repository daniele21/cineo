import Foundation
import Combine
import AppKit
import CineoMusic

/// Owns only an ace-server process explicitly started by Cineo.
/// Existing user-launched servers may be used but are never terminated.
@MainActor
final class CineoACEBackendController: ObservableObject {
    enum Phase: String {
        case stopped, checking, missing, launching, ready, failed
    }

    @Published private(set) var phase: Phase = .stopped
    @Published private(set) var detail = "Verifica il motore locale per generare musica."
    @Published private(set) var recentLog = ""
    @Published private(set) var isManaged = false
    @Published private(set) var selectedRoot: URL?

    private let locationKey = "Cineo.music.aceBackendDirectory"
    private var server: Process?
    private var outputPipe: Pipe?
    private var launchingTask: Task<Void, Never>?

    init() {
        if let stored = UserDefaults.standard.string(forKey: locationKey), !stored.isEmpty {
            selectedRoot = URL(fileURLWithPath: stored, isDirectory: true)
        } else {
            selectedRoot = CineoACEBackendInstallation.candidateRoots().first {
                FileManager.default.isExecutableFile(
                    atPath: CineoACEBackendInstallation(root: $0).executableURL.path)
            } ?? CineoACEBackendInstallation.candidateRoots().first {
                FileManager.default.fileExists(atPath: $0.appendingPathComponent("models").path)
            }
        }
    }

    var installation: CineoACEBackendInstallation? {
        selectedRoot.map { CineoACEBackendInstallation(root: $0) }
    }

    var isReady: Bool { phase == .ready }
    var isBusy: Bool { phase == .checking || phase == .launching }

    var missingModels: [String] {
        installation?.unavailableModels() ?? CineoACEBackendInstallation.requiredModels
    }

    func chooseFolder() {
        guard !isBusy, server?.isRunning != true else {
            detail = "Arresta prima il server avviato da Cineo."
            return
        }
        let picker = NSOpenPanel()
        picker.canChooseFiles = false
        picker.canChooseDirectories = true
        picker.allowsMultipleSelection = false
        picker.prompt = "Usa questa cartella"
        picker.message = "Seleziona la cartella acestep.cpp con build/ace-server e models/."
        if picker.runModal() == .OK, let url = picker.url {
            selectedRoot = url.standardizedFileURL.resolvingSymlinksInPath()
            UserDefaults.standard.set(selectedRoot?.path, forKey: locationKey)
            phase = .stopped
            detail = "Cartella selezionata. Verifica i modelli e lo stato del server."
        }
    }

    func revealModels() {
        guard let installation else { return }
        NSWorkspace.shared.activateFileViewerSelecting([installation.modelsURL])
    }

    func refresh() async {
        guard !isBusy else { return }
        phase = .checking
        do {
            try await ping()
            phase = .ready
            isManaged = server?.isRunning == true
            detail = isManaged
                ? "ACE-Step locale attivo, avviato da Cineo."
                : "ACE-Step locale attivo (server già avviato esternamente)."
        } catch {
            if server?.isRunning == true {
                phase = .launching
                detail = "Server avviato, ma l'endpoint /health non è ancora pronto."
            } else {
                isManaged = false
                phase = .stopped
                if let installation, !installation.unavailableModels().isEmpty {
                    phase = .missing
                    detail = "Mancano modelli GGUF validi. Completa ./models.sh nella cartella ACE-Step."
                } else if installation == nil {
                    phase = .missing
                    detail = "Seleziona la cartella locale di ACE-Step."
                } else {
                    detail = "Server locale non avviato. Puoi avviarlo dalla UI."
                }
            }
        }
    }

    func start() {
        guard server?.isRunning != true, !isBusy else { return }
        guard let installation else {
            phase = .missing
            detail = "Seleziona prima la cartella acestep.cpp."
            return
        }
        do {
            try installation.validateForLaunch()
            // Never launch a second server when another process already owns
            // the localhost port; refresh must identify the external instance.
            launchingTask?.cancel()
            phase = .launching
            detail = "Avvio ACE-Step su 127.0.0.1:8080…"
            recentLog = ""
            let process = Process()
            process.executableURL = installation.executableURL
            process.arguments = installation.launchArguments
            process.currentDirectoryURL = installation.root
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = pipe
            outputPipe = pipe
            pipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
                let chunk = handle.availableData
                guard !chunk.isEmpty else { return }
                let message = String(decoding: chunk, as: UTF8.self)
                Task { @MainActor [weak self] in self?.appendLog(message) }
            }
            process.terminationHandler = { [weak self] terminated in
                let code = terminated.terminationStatus
                Task { @MainActor [weak self] in
                    guard let self, self.server === terminated else { return }
                    self.outputPipe?.fileHandleForReading.readabilityHandler = nil
                    self.outputPipe = nil
                    self.server = nil
                    self.isManaged = false
                    if self.phase != .stopped {
                        self.phase = .failed
                        self.detail = "ACE-Step terminato (codice \(code)). Controlla i log."
                    }
                }
            }
            try process.run()
            server = process
            isManaged = true
            launchingTask = Task { [weak self] in
                for attempt in 0..<30 {
                    guard let self else { return }
                    if Task.isCancelled { return }
                    do {
                        try await self.ping()
                        self.phase = .ready
                        self.detail = "ACE-Step pronto per generare musica su localhost."
                        return
                    } catch {
                        if self.server?.isRunning != true {
                            self.phase = .failed
                            self.detail = "Il server si è arrestato. Consulta i log."
                            return
                        }
                    }
                    self.detail = "Avvio motore locale, verifica \(attempt + 1)/30 (non è la percentuale di generazione)…"
                    try? await Task.sleep(for: .seconds(1))
                }
                self?.phase = .failed
                self?.detail = "ACE-Step non risponde dopo 30 s. Consulta i log; il processo può essere ancora attivo."
            }
        } catch {
            outputPipe?.fileHandleForReading.readabilityHandler = nil
            outputPipe = nil
            phase = .failed
            detail = "Avvio ACE-Step fallito: \(error.localizedDescription)"
        }
    }

    func stop() {
        launchingTask?.cancel()
        launchingTask = nil
        guard let owned = server, owned.isRunning else {
            detail = "Server non gestito da Cineo: non lo arresto."
            return
        }
        phase = .stopped
        detail = "Arresto del motore ACE-Step avviato da Cineo…"
        owned.terminate()
    }

    private func ping() async throws {
        // Health is checked with a short timeout; generation retains the
        // ordinary client request timeouts and is managed separately.
        let endpoint = URL(string: "http://127.0.0.1:8080/health")!
        var request = URLRequest(url: endpoint)
        request.timeoutInterval = 3
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let response = response as? HTTPURLResponse, response.statusCode == 200,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: String],
              json["status"] == "ok" else {
            throw CineoMusicError.unavailable("ACE-Step /health non risponde correttamente.")
        }
    }

    private func appendLog(_ message: String) {
        recentLog += message
        if recentLog.count > 8_000 {
            recentLog = String(recentLog.suffix(8_000))
        }
    }
}
