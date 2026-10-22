import Foundation

/// Explicit source-relative inpaint of an existing WAV/MP3. In contrast to
/// music.generate, this calls ACE-Step /synth directly with source audio and
/// never invokes /lm. Originals are immutable.
public struct CineoACERepaintRequest: Codable, Equatable, Sendable {
    public let sourceStart: Double
    public let sourceEnd: Double
    public let sourceDuration: Double
    public let prompt: String
    public let seed: Int64

    public init(sourceStart: Double, sourceEnd: Double, sourceDuration: Double,
                prompt: String, seed: Int64 = -1) {
        self.sourceStart = sourceStart
        self.sourceEnd = sourceEnd
        self.sourceDuration = sourceDuration
        self.prompt = prompt
        self.seed = seed
    }

    public func validate() throws {
        guard sourceDuration.isFinite, sourceDuration > 2,
              sourceDuration <= 600,
              sourceStart.isFinite, sourceEnd.isFinite,
              sourceStart >= 0, sourceEnd <= sourceDuration,
              sourceEnd - sourceStart >= 1,
              sourceEnd - sourceStart <= 120,
              !prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              prompt.utf8.count <= 4000 else {
            throw CineoMusicError.invalid(
                "Repaint: seleziona tra 1 e 120 secondi dentro la traccia e una descrizione musicale.")
        }
    }

    public func jsonBody() throws -> Data {
        try validate()
        let request: [String: Any] = [
            "task_type": "repaint",
            "caption": prompt,
            "lyrics": "[Instrumental]",
            "repainting_start": sourceStart,
            "repainting_end": sourceEnd,
            "inference_steps": 8,
            "guidance_scale": 1.0,
            "shift": 1.0,
            "output_format": "wav16",
            "seed": seed,
            "synth_batch_size": 1,
            "use_cot_caption": false
        ]
        return try JSONSerialization.data(withJSONObject: request, options: .sortedKeys)
    }

    /// Maps a visible output-time window to the underlying music file;
    /// deliberately rejects clip loops that cross a repeat boundary.
    public static func fromVideoSelection(start: Double, end: Double,
                        clip: CineoMusicClip, offset: Double,
                        sourceDuration: Double, videoDuration: Double,
                        prompt: String, seed: Int64) throws -> CineoACERepaintRequest {
        guard start.isFinite, end.isFinite, end > start,
              start >= offset, end <= videoDuration else {
            throw CineoMusicError.invalid("Selezione video fuori dalla clip musicale.")
        }
        let a = clip.previewLayers(videoTime: start,
            sourceDuration: sourceDuration, videoDuration: videoDuration,
            offset: offset)
        let b = clip.previewLayers(videoTime: end - 0.00001,
            sourceDuration: sourceDuration, videoDuration: videoDuration,
            offset: offset)
        guard a.count == 1, b.count == 1,
              a[0].repeatIndex == b[0].repeatIndex,
              a[0].gain >= 0.999, b[0].gain >= 0.999 else {
            throw CineoMusicError.invalid(
                "Repaint non disponibile se la selezione attraversa un loop o un crossfade.")
        }
        let proposed = CineoACERepaintRequest(sourceStart: a[0].sourcePosition,
                            sourceEnd: b[0].sourcePosition + 0.00001,
                            sourceDuration: sourceDuration, prompt: prompt, seed: seed)
        try proposed.validate()
        return proposed
    }
}

/// Pure, auditable multipart/form-data builder for the documented ace-server
/// POST /synth endpoint: fields named "request" and "audio".
public enum CineoACEMultipartRepaint {
    public static func make(request: CineoACERepaintRequest,
                            source: Data, extension ext: String,
                            boundary: String) throws -> Data {
        let json = try request.jsonBody()
        guard ["wav", "mp3"].contains(ext.lowercased()),
              !source.isEmpty, source.count <= 125_000_000,
              boundary.count >= 16, boundary.count <= 100,
              boundary.utf8.allSatisfy({ $0 == 45 || $0 == 95 ||
                                         ($0 >= 48 && $0 <= 57) ||
                                         ($0 >= 65 && $0 <= 90) ||
                                         ($0 >= 97 && $0 <= 122) })
        else { throw CineoMusicError.invalid("File sorgente, formato o boundary repaint non valido.") }
        var out = Data()
        func append(_ string: String) { out.append(contentsOf: string.utf8) }
        append("--\(boundary)\r\n")
        append("Content-Disposition: form-data; name=\"request\"; filename=\"request.json\"\r\n")
        append("Content-Type: application/json\r\n\r\n")
        out.append(json)
        append("\r\n--\(boundary)\r\n")
        append("Content-Disposition: form-data; name=\"audio\"; filename=\"source.\(ext)\"\r\n")
        append("Content-Type: \(ext == "mp3" ? "audio/mpeg" : "audio/wav")\r\n\r\n")
        out.append(source)
        append("\r\n--\(boundary)--\r\n")
        return out
    }
}
