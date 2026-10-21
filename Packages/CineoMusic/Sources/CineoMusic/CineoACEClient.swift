import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Real adapter for ServeurpersoCom/acestep.cpp ace-server asynchronous API.
/// Uses the two-stage /lm -> /synth job protocol, not a mock endpoint.
public struct CineoACEClient: Sendable {
    public let baseURL: URL
    private let session: URLSession

    public init(baseURL: URL = URL(string: "http://127.0.0.1:8080")!,
                session: URLSession = .shared) throws {
        guard baseURL.scheme == "http",
              ["127.0.0.1", "localhost", "::1"].contains(baseURL.host ?? ""),
              baseURL.user == nil, baseURL.password == nil,
              baseURL.path.isEmpty || baseURL.path == "/",
              baseURL.query == nil, baseURL.fragment == nil,
              baseURL.port != 0 else {
            throw CineoMusicError.invalid("ACE-Step deve usare un server locale (loopback HTTP).")
        }
        self.baseURL = baseURL
        self.session = session
    }

    public func healthCheck() async throws {
        let (data, _) = try await send(path: "/health", method: "GET")
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: String],
              json["status"] == "ok" else {
            throw CineoMusicError.unavailable("ACE-Step non è pronto. Avvia ace-server con i modelli GGUF.")
        }
    }

    /// Calls onStatus at each real stage. The synthesis result is stored
    /// atomically only after receiving a valid WAV payload.
    @discardableResult
    public func generate(settings: CineoMusicSettings, destination: URL,
                         onStatus: @escaping @Sendable (String) -> Void = { _ in }) async throws -> URL {
        try settings.validate()
        guard destination.isFileURL, destination.pathExtension.lowercased() == "wav",
              !FileManager.default.fileExists(atPath: destination.path) else {
            throw CineoMusicError.invalid("Destinazione WAV non valida o già esistente.")
        }
        onStatus("Connessione al motore ACE-Step…")
        try await healthCheck()
        let initial = try settings.aceRequest()
        onStatus("ACE-Step: preparazione musicale (LM interno)…")
        let lm = try await submit("/lm", data: initial)
        var activeJob = lm
        do {
            try await waitForJob(lm)
            let (lmData, _) = try await send(path: "/job", method: "GET",
                                              query: ["id": lm, "result": "1"])
            let items = try JSONSerialization.jsonObject(with: lmData) as? [[String: Any]]
            guard let first = items?.first else {
                throw CineoMusicError.server("ACE-Step /lm non ha restituito codici musicali.")
            }
            let synthJSON = try JSONSerialization.data(withJSONObject: first)
            onStatus("ACE-Step: sintesi strumentale (DiT + VAE)…")
            let synth = try await submit("/synth", data: synthJSON)
            activeJob = synth
            try await waitForJob(synth)
            onStatus("Recupero traccia audio generata…")
            let (result, response) = try await send(path: "/job", method: "GET",
                                                      query: ["id": synth, "result": "1"])
            let wav = try Self.wavPayload(result,
                                contentType: response.value(forHTTPHeaderField: "Content-Type") ?? "")
            guard wav.count > 44, wav.prefix(4) == Data("RIFF".utf8),
                  wav.dropFirst(8).prefix(4) == Data("WAVE".utf8) else {
                throw CineoMusicError.server("ACE-Step non ha restituito un file WAV valido.")
            }
            try Task.checkCancellation()
            try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(),
                                                    withIntermediateDirectories: true)
            let temp = destination.deletingLastPathComponent().appendingPathComponent("." + UUID().uuidString + ".wav")
            defer { try? FileManager.default.removeItem(at: temp) }
            try wav.write(to: temp, options: .atomic)
            try Task.checkCancellation()
            try FileManager.default.moveItem(at: temp, to: destination)
            onStatus("Traccia musicale generata.")
            return destination
        } catch {
            let job = activeJob
            // The parent task can be cancelled; issue server cancellation from
            // a fresh context so compute does not keep running unnecessarily.
            if error is CancellationError {
                let base = self
                Task.detached { try? await base.cancelJob(job) }
            }
            throw error
        }
    }

    private func submit(_ path: String, data: Data) async throws -> String {
        let (responseData, _) = try await send(path: path, method: "POST", body: data)
        guard let object = try? JSONSerialization.jsonObject(with: responseData) as? [String: Any],
              let id = object["id"] as? String, !id.isEmpty,
              id.count < 100, id.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-" || $0 == "_") })
        else { throw CineoMusicError.server("Risposta job ACE-Step non valida.") }
        return id
    }

    private func waitForJob(_ id: String) async throws {
        for _ in 0..<1800 { // at most 30 minutes, poll every second
            try Task.checkCancellation()
            let (data, _) = try await send(path: "/job", method: "GET", query: ["id": id])
            guard let status = (try? JSONSerialization.jsonObject(with: data) as? [String: String])?["status"] else {
                throw CineoMusicError.server("Stato job ACE-Step non valido.")
            }
            switch status {
            case "done": return
            case "failed", "cancelled": throw CineoMusicError.server("ACE-Step: job " + status)
            case "queued", "running": break
            default: throw CineoMusicError.server("Stato ACE-Step sconosciuto: " + status)
            }
            try await Task.sleep(for: .seconds(1))
        }
        throw CineoMusicError.unavailable("ACE-Step ha superato il limite di 30 minuti.")
    }

    private func cancelJob(_ id: String) async throws {
        _ = try await send(path: "/job", method: "POST", query: ["id": id, "cancel": "1"])
    }

    private func send(path: String, method: String, query: [String: String] = [:],
                      body: Data? = nil) async throws -> (Data, HTTPURLResponse) {
        guard var c = URLComponents(url: baseURL, resolvingAgainstBaseURL: false) else {
            throw CineoMusicError.invalid("URL locale ACE-Step non valido.")
        }
        c.path = path
        c.queryItems = query.sorted { $0.key < $1.key }
            .map { URLQueryItem(name: $0.key, value: $0.value) }
        guard let url = c.url else { throw CineoMusicError.invalid("URL job ACE-Step non valido.") }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.timeoutInterval = 120
        if let body { request.httpBody = body; request.setValue("application/json", forHTTPHeaderField: "Content-Type") }
        let data: Data
        let response: URLResponse
        do { (data, response) = try await session.data(for: request) }
        catch is CancellationError { throw CancellationError() }
        catch { throw CineoMusicError.unavailable("Impossibile contattare ACE-Step locale: " + error.localizedDescription) }
        guard let http = response as? HTTPURLResponse else {
            throw CineoMusicError.server("Risposta non HTTP da ACE-Step.")
        }
        guard (200..<300).contains(http.statusCode) else {
            throw CineoMusicError.server("ACE-Step HTTP \(http.statusCode): " +
                String(decoding: data.prefix(500), as: UTF8.self))
        }
        return (data, http)
    }

    /// Extract the first WAV audio part of ace-server's multipart/mixed result.
    /// It also accepts raw audio/wav for backend compatibility.
    public static func wavPayload(_ data: Data, contentType: String) throws -> Data {
        guard contentType.lowercased().contains("multipart/") else { return data }
        guard let rawBoundary = contentType.split(separator: ";")
            .map({ $0.trimmingCharacters(in: .whitespaces) })
            .first(where: { $0.lowercased().hasPrefix("boundary=") })?
            .split(separator: "=", maxSplits: 1).last else {
            throw CineoMusicError.server("Multipart ACE-Step senza boundary.")
        }
        let boundary = rawBoundary.trimmingCharacters(in: CharacterSet(charactersIn: "\""))
        guard !boundary.isEmpty, boundary.count < 150 else {
            throw CineoMusicError.server("Boundary ACE-Step non valido.")
        }
        let delimiter = Data(("--" + boundary).utf8)
        let headerSep = Data("\r\n\r\n".utf8)
        var cursor = data.startIndex
        while let marker = data.range(of: delimiter, in: cursor..<data.endIndex) {
            let sectionStart = marker.upperBound
            guard let next = data.range(of: delimiter, in: sectionStart..<data.endIndex) else { break }
            if let endOfHeader = data.range(of: headerSep, in: sectionStart..<next.lowerBound) {
                let header = String(decoding: data[sectionStart..<endOfHeader.lowerBound], as: UTF8.self).lowercased()
                if header.contains("audio/wav") || header.contains("audio/x-wav") || header.contains("audio/wave") {
                    var end = next.lowerBound
                    if end >= 2 && data[end - 2] == 13 && data[end - 1] == 10 { end -= 2 }
                    return data.subdata(in: endOfHeader.upperBound..<end)
                }
            }
            cursor = next.lowerBound
        }
        throw CineoMusicError.server("Multipart ACE-Step non contiene audio WAV.")
    }
}
