import Foundation
import Combine
import AppKit
import CineoMusic

/// An explicit user-triggered GGUF download through the already installed
/// Hugging Face CLI. It never runs shell scripts, uses no remote API tokens,
/// and does not claim precise network progress (only files completed).
@MainActor
final class CineoACEModelDownloader: ObservableObject {
    @Published private(set) var isDownloading = false
    @Published private(set) var completedFiles = 0
    @Published private(set) var totalFiles = 0
    @Published private(set) var status = ""
    @Published private(set) var log = ""

    private var task: Task<Void, Never>?
    private var process: Process?
    private var pipe: Pipe?

    private static func cliURL() -> URL? {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let environmentPaths = (ProcessInfo.processInfo.environment["PATH"] ?? "")
            .split(separator: ":").map { URL(fileURLWithPath: String($0)).appendingPathComponent("hf") }
        let known = [
            home.appendingPathComponent(".local/bin/hf"),
            URL(fileURLWithPath: "/opt/homebrew/bin/hf"),
            URL(fileURLWithPath: "/usr/local/bin/hf")
        ]
        return (known + environmentPaths).first {
            $0.isFileURL && FileManager.default.isExecutableFile(atPath: $0.path)
        }
    }

    func downloadMissing(installation: CineoACEBackendInstallation,
                         onCompleted: @escaping @MainActor () -> Void) {
        guard !isDownloading else { return }
        let missing = installation.unavailableModels()
        guard !missing.isEmpty else {
            status = "Tutti e quattro i GGUF sono già presenti."
            onCompleted()
            return
        }
        guard let executable = Self.cliURL() else {
            status = "CLI Hugging Face non trovata. Installa 'hf' e verifica 'hf --help' nel Terminale."
            return
        }
        let expected: [String: Int64] = [
            "vae-BF16.gguf": 350_000_000,
            "Qwen3-Embedding-0.6B-Q8_0.gguf": 800_000_000,
            "acestep-5Hz-lm-4B-Q8_0.gguf": 4_600_000_000,
            "acestep-v15-turbo-Q8_0.gguf": 2_600_000_000
        ]
        let estimatedBytes = missing.reduce(Int64(0)) { $0 + (expected[$1] ?? 0) }
        do {
            try FileManager.default.createDirectory(at: installation.modelsURL,
                                                    withIntermediateDirectories: true)
            if let attributes = try? FileManager.default.attributesOfFileSystem(
                 forPath: installation.root.path),
               let free = attributes[.systemFreeSize] as? NSNumber,
               free.int64Value < estimatedBytes + 4_000_000_000 {
                status = "Spazio insufficiente per scaricare i modelli in sicurezza. Libera spazio sul disco."
                return
            }
        } catch {
            status = "Impossibile creare la cartella modelli: \(error.localizedDescription)"
            return
        }
        isDownloading = true
        completedFiles = 0
        totalFiles = missing.count
        log = ""
        task = Task { [weak self] in
            guard let self else { return }
            do {
                for (index, name) in missing.enumerated() {
                    try Task.checkCancellation()
                    status = "Download GGUF \(index + 1)/\(missing.count): \(name). Nessuna percentuale stimata."
                    let p = Process()
                    p.executableURL = executable
                    p.currentDirectoryURL = installation.root
                    p.arguments = [
                        "download", "--quiet", "Serveurperso/ACE-Step-1.5-GGUF",
                        name, "--local-dir", installation.modelsURL.path
                    ]
                    let output = Pipe()
                    p.standardOutput = output
                    p.standardError = output
                    pipe = output
                    output.fileHandleForReading.readabilityHandler = { [weak self] handle in
                        let data = handle.availableData
                        guard !data.isEmpty else { return }
                        let message = String(decoding: data, as: UTF8.self)
                        Task { @MainActor [weak self] in self?.appendLog(message) }
                    }
                    try p.run()
                    process = p
                    while p.isRunning {
                        try Task.checkCancellation()
                        try await Task.sleep(for: .milliseconds(250))
                    }
                    output.fileHandleForReading.readabilityHandler = nil
                    pipe = nil
                    process = nil
                    guard p.terminationStatus == 0,
                          !installation.unavailableModels().contains(name) else {
                        throw CineoMusicError.unavailable(
                            "Download incompleto di \(name) (codice \(p.terminationStatus)).")
                    }
                    completedFiles = index + 1
                }
                status = "Tutti i modelli GGUF necessari sono stati scaricati."
                onCompleted()
            } catch is CancellationError {
                if let process = self.process, process.isRunning { process.terminate() }
                status = "Download interrotto. Potrai riprendere scaricando i modelli mancanti."
            } catch {
                status = "Download GGUF fallito: \(error.localizedDescription)"
            }
            self.pipe?.fileHandleForReading.readabilityHandler = nil
            self.pipe = nil
            self.process = nil
            self.isDownloading = false
            self.task = nil
        }
    }

    func cancel() {
        task?.cancel()
        if let process, process.isRunning { process.terminate() }
    }

    private func appendLog(_ value: String) {
        log += value
        if log.count > 5_000 { log = String(log.suffix(5_000)) }
    }
}
