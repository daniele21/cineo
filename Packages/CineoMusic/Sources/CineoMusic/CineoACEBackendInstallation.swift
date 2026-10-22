import Foundation

/// Local-only backend setup contract. Does not download or execute anything.
/// Cineo intentionally never bundles GGUF weights in its signed .app.
public struct CineoACEBackendInstallation: Sendable {
    public static let requiredModels: [String] = [
        "vae-BF16.gguf",
        "Qwen3-Embedding-0.6B-Q8_0.gguf",
        "acestep-5Hz-lm-4B-Q8_0.gguf",
        "acestep-v15-turbo-Q8_0.gguf"
    ]
    public let root: URL

    public init(root: URL) {
        self.root = root.standardizedFileURL.resolvingSymlinksInPath()
    }

    public var executableURL: URL { root.appendingPathComponent("build/ace-server") }
    public var modelsURL: URL { root.appendingPathComponent("models", isDirectory: true) }

    public func validateForLaunch() throws {
        guard root.isFileURL, modelsURL.isFileURL else {
            throw CineoMusicError.invalid("Seleziona una cartella ACE-Step locale.")
        }
        var directory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: root.path, isDirectory: &directory),
              directory.boolValue else {
            throw CineoMusicError.unavailable("La cartella ACE-Step non esiste.")
        }
        guard FileManager.default.isExecutableFile(atPath: executableURL.path) else {
            throw CineoMusicError.unavailable(
                "Manca build/ace-server. Compila ACE-Step prima di avviare il motore.")
        }
        let missing = unavailableModels()
        guard missing.isEmpty else {
            throw CineoMusicError.unavailable(
                "Modelli ACE-Step assenti o incompleti: " + missing.joined(separator: ", ") +
                ". Completa ./models.sh dalla cartella selezionata.")
        }
    }

    /// Check a minimum size and GGUF magic to catch interrupted downloads and
    /// mislabeled files; not a full checksum or model-load validation.
    public func unavailableModels() -> [String] {
        Self.requiredModels.filter { model in
            let url = modelsURL.appendingPathComponent(model)
            guard url.standardizedFileURL.resolvingSymlinksInPath()
                .deletingLastPathComponent() == modelsURL.standardizedFileURL.resolvingSymlinksInPath(),
                  let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
                  let bytes = attributes[.size] as? NSNumber,
                  bytes.int64Value >= 1_048_576,
                  let file = try? FileHandle(forReadingFrom: url) else { return true }
            defer { try? file.close() }
            return (try? file.read(upToCount: 4)) != Data("GGUF".utf8)
        }
    }

    public var launchArguments: [String] {
        ["--host", "127.0.0.1", "--port", "8080", "--models", modelsURL.path]
    }

    /// Safe suggestions only; never automatically clone or download weights.
    public static func candidateRoots(home: URL = FileManager.default.homeDirectoryForCurrentUser,
                                      workingDirectory: URL = URL(fileURLWithPath:
                                          FileManager.default.currentDirectoryPath)) -> [URL] {
        let candidates = [
            workingDirectory.appendingPathComponent("acestep.cpp"),
            workingDirectory.appendingPathComponent("../acestep.cpp"),
            home.appendingPathComponent("Personal/cineo/acestep.cpp"),
            home.appendingPathComponent("Personal/acestep.cpp")
        ].map { $0.standardizedFileURL.resolvingSymlinksInPath() }
        var seen = Set<String>()
        return candidates.filter { seen.insert($0.path).inserted }
    }
}
