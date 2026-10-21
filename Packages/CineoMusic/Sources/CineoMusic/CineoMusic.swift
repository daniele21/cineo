import Foundation

/// Editable music intent. No assistant or external LLM is needed to create this.
public struct CineoMusicSettings: Codable, Equatable, Sendable {
    public var caption: String
    public var bpm: Int
    public var duration: Double
    public var keyscale: String
    public var seed: Int64
    public var volume: Double
    public var offset: Double
    public var fadeIn: Double
    public var fadeOut: Double

    public init(caption: String = "Modern minimal electronic instrumental music, warm synths, subtle rhythmic pulse, elegant product demo background",
                bpm: Int = 110, duration: Double = 30, keyscale: String = "C major",
                seed: Int64 = -1, volume: Double = 0.4, offset: Double = 0,
                fadeIn: Double = 0.6, fadeOut: Double = 1.5) {
        self.caption = caption
        self.bpm = bpm
        self.duration = duration
        self.keyscale = keyscale
        self.seed = seed
        self.volume = volume
        self.offset = offset
        self.fadeIn = fadeIn
        self.fadeOut = fadeOut
    }

    public func validate(videoDuration: Double? = nil) throws {
        guard !caption.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              caption.utf8.count <= 4000 else { throw CineoMusicError.invalid("Descrizione musicale obbligatoria (max 4000 byte).") }
        guard (40...240).contains(bpm), duration.isFinite, (10...600).contains(duration),
              keyscale.utf8.count <= 60, !keyscale.isEmpty,
              volume.isFinite, (0...1).contains(volume),
              offset.isFinite, offset >= 0,
              fadeIn.isFinite, fadeIn >= 0, fadeIn <= duration,
              fadeOut.isFinite, fadeOut >= 0, fadeOut <= duration
        else { throw CineoMusicError.invalid("Parametri musicali fuori intervallo.") }
        if let videoDuration {
            guard videoDuration.isFinite, videoDuration > 0, offset < videoDuration else {
                throw CineoMusicError.invalid("La traccia deve iniziare durante il video.")
            }
        }
    }

    /// Explicit metadata avoids LM creative prompt suggestions. ACE-Step still
    /// uses its *internal* LM to produce music codes before DiT synthesis.
    public func aceRequest() throws -> Data {
        try validate()
        let payload: [String: Any] = [
            "caption": caption,
            "lyrics": "[Instrumental]",
            "duration": duration,
            "bpm": bpm,
            "keyscale": keyscale,
            "timesignature": "4",
            "vocal_language": "unknown",
            "task_type": "text2music",
            "output_format": "wav16",
            "seed": seed,
            "use_cot_caption": false,
            "lm_batch_size": 1,
            "synth_batch_size": 1
        ]
        return try JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys])
    }
}

/// Local asset reference; never store absolute paths in project packages.
public struct CineoMusicAsset: Codable, Equatable, Sendable {
    public var fileName: String
    public var settings: CineoMusicSettings

    public init(fileName: String, settings: CineoMusicSettings) {
        self.fileName = fileName
        self.settings = settings
    }

    public func validate() throws {
        guard !fileName.isEmpty, !fileName.contains("/"), !fileName.contains("\\"),
              fileName != ".", fileName != "..", !fileName.hasPrefix("."),
              ["wav", "mp3", "m4a", "aiff", "aac"].contains((fileName as NSString).pathExtension.lowercased())
        else { throw CineoMusicError.invalid("Nome della traccia musicale non valido.") }
        try settings.validate()
    }
}

public enum CineoMusicError: LocalizedError, Sendable {
    case invalid(String)
    case unavailable(String)
    case server(String)

    public var errorDescription: String? {
        switch self {
        case .invalid(let message), .unavailable(let message), .server(let message): return message
        }
    }
}
