import Foundation

/// Documented, bounded, strict v1 input for camera actions and stage styles.
/// This is an interchange format, not a second renderer or project model:
/// it compiles into the existing CineoScenePlan used by preview and export.
public struct CineoInstructionDocument: Codable, Sendable {
    public let version: Int
    public let timebase: String
    public let stage: Stage?
    public let actions: [Action]

    public struct Stage: Codable, Sendable {
        /// "16:9" or "9:16". Missing values preserve the editor setting.
        public let aspect: String?
        /// "dark", "black" or "light".
        public let background: String?
        public let padding: Double?
    }

    public struct Action: Codable, Sendable {
        public let id: String
        public let type: String
        public let start: Double
        public let end: Double
        public let target: Target
        public let scale: Double
        public let transition: Transition
    }

    public struct Target: Codable, Sendable {
        /// Normalized coordinates in recorded screen space; origin top-left.
        public let x: Double
        public let y: Double
    }

    public struct Transition: Codable, Sendable {
        /// Durations (seconds) for camera arrival and departure.
        public let `in`: Double
        public let out: Double
    }

    /// Decode strict JSON and reject silently ignored fields.
    /// Deliberately no executable expressions, network links, or plugins.
    public static func decode(_ data: Data) throws -> CineoInstructionDocument {
        guard !data.isEmpty, data.count <= 1_048_576 else {
            throw CineoInstructionError.invalid("Il JSON deve occupare al massimo 1 MB.")
        }
        let any: Any
        do { any = try JSONSerialization.jsonObject(with: data) }
        catch { throw CineoInstructionError.invalid("JSON non valido: \(error.localizedDescription)") }
        guard let root = any as? [String: Any] else {
            throw CineoInstructionError.invalid("La radice del documento deve essere un oggetto JSON.")
        }
        try fields(root, allowed: ["version", "timebase", "stage", "actions"], at: "root")
        if let raw = root["stage"] {
            guard let stage = raw as? [String: Any] else {
                throw CineoInstructionError.invalid("stage deve essere un oggetto.")
            }
            try fields(stage, allowed: ["aspect", "background", "padding"], at: "stage")
        }
        guard let rawActions = root["actions"] as? [[String: Any]] else {
            throw CineoInstructionError.invalid("actions deve essere un array di oggetti.")
        }
        guard rawActions.count <= 200 else {
            throw CineoInstructionError.invalid("Massimo 200 azioni per documento.")
        }
        for (index, action) in rawActions.enumerated() {
            let prefix = "actions[\(index)]"
            try fields(action, allowed: ["id", "type", "start", "end", "target", "scale", "transition"], at: prefix)
            guard let target = action["target"] as? [String: Any],
                  let transition = action["transition"] as? [String: Any] else {
                throw CineoInstructionError.invalid("\(prefix): target e transition sono obbligatori.")
            }
            try fields(target, allowed: ["x", "y"], at: "\(prefix).target")
            try fields(transition, allowed: ["in", "out"], at: "\(prefix).transition")
        }
        do { return try JSONDecoder().decode(Self.self, from: data) }
        catch { throw CineoInstructionError.invalid("Campi mancanti o tipi JSON errati: \(error.localizedDescription)") }
    }

    /// Completely validate before the app changes any existing camera edits.
    public func compile(duration: Double, over existing: CineoScenePlan) throws -> CineoScenePlan {
        guard version == 1, timebase == "output" else {
            throw CineoInstructionError.invalid("Supportati solo version=1 e timebase=output.")
        }
        guard duration.isFinite, duration > 0 else {
            throw CineoInstructionError.invalid("La durata della sorgente non è valida.")
        }
        guard !actions.isEmpty || stage != nil else {
            throw CineoInstructionError.invalid("Documento senza azioni né composizione.")
        }
        var plan = existing
        if let stage {
            if let aspect = stage.aspect {
                switch aspect {
                case "16:9": plan.outputWidth = 1920; plan.outputHeight = 1080
                case "9:16": plan.outputWidth = 1080; plan.outputHeight = 1920
                default: throw CineoInstructionError.invalid("stage.aspect: usare 16:9 o 9:16.")
                }
            }
            if let background = stage.background {
                switch background {
                case "dark": plan.background = .init(red: 0.09, green: 0.12, blue: 0.19)
                case "black": plan.background = .init(red: 0.015, green: 0.017, blue: 0.025)
                case "light": plan.background = .init(red: 0.91, green: 0.93, blue: 0.97)
                default: throw CineoInstructionError.invalid("stage.background: usare dark, black o light.")
                }
            }
            if let padding = stage.padding {
                guard padding.isFinite, (0..<0.35).contains(padding) else {
                    throw CineoInstructionError.invalid("stage.padding deve essere fra 0 e 0.35 (escluso).")
                }
                plan.paddingFraction = padding
            }
        }
        // In v1 an import replaces the camera sequence. UI must ask permission
        // if manually authored keyframes would be lost.
        let sorted = actions.sorted { $0.start < $1.start }
        var result: [CineoCameraKeyframe] = []
        var seenIDs = Set<String>()
        var lastEnd = -Double.infinity
        let validID = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_-")
        for action in sorted {
            guard !action.id.isEmpty, action.id.count <= 80,
                  action.id.unicodeScalars.allSatisfy({ validID.contains($0) }),
                  seenIDs.insert(action.id).inserted else {
                throw CineoInstructionError.invalid("ID di azione duplicato o non valido: \(action.id).")
            }
            guard action.type == "camera.zoom" else {
                throw CineoInstructionError.invalid("Azione non supportata: \(action.type). Nessun effetto viene ignorato.")
            }
            guard action.start.isFinite, action.end.isFinite,
                  action.start >= 0, action.end <= duration,
                  action.end > action.start,
                  action.start > lastEnd,
                  action.scale.isFinite, (1.01...2.5).contains(action.scale),
                  action.target.x.isFinite, (0...1).contains(action.target.x),
                  action.target.y.isFinite, (0...1).contains(action.target.y),
                  action.transition.in.isFinite, action.transition.out.isFinite,
                  action.transition.in >= 0.05, action.transition.out >= 0.05,
                  action.start + action.transition.in + 0.05 <= action.end - action.transition.out
            else {
                throw CineoInstructionError.invalid("Azione \(action.id): intervallo, zoom, coordinate o transizioni non validi / sovrapposti.")
            }
            lastEnd = action.end
            let overview = (zoom: 1.0, x: 0.5, y: 0.5)
            result.append(.init(time: action.start, zoom: overview.zoom,
                                focusX: overview.x, focusY: overview.y))
            result.append(.init(time: action.start + action.transition.in, zoom: action.scale,
                                focusX: action.target.x, focusY: action.target.y))
            result.append(.init(time: action.end - action.transition.out, zoom: action.scale,
                                focusX: action.target.x, focusY: action.target.y))
            result.append(.init(time: action.end, zoom: overview.zoom,
                                focusX: overview.x, focusY: overview.y))
        }
        plan.camera = result
        try plan.validate()
        return plan
    }

    private static func fields(_ object: [String: Any], allowed: Set<String>, at path: String) throws {
        let extra = Set(object.keys).subtracting(allowed)
        if let unexpected = extra.sorted().first {
            throw CineoInstructionError.invalid("\(path): campo non supportato '\(unexpected)'.")
        }
    }
}

public enum CineoInstructionError: LocalizedError, Sendable {
    case invalid(String)

    public var errorDescription: String? {
        switch self {
        case .invalid(let message): return message
        }
    }
}
