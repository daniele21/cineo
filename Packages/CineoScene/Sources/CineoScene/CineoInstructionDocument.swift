import Foundation

/// Documented, bounded, strict v1 input for camera actions and stage styles.
/// This is an interchange format, not a second renderer or project model:
/// it compiles into the existing CineoScenePlan used by preview and export.
public struct CineoInstructionDocument: Codable, Sendable {
    public let version: Int
    public let timebase: String
    public let stage: Stage?
    public let actions: [Action]

    public init(version: Int = 1, timebase: String = "output", stage: Stage?, actions: [Action]) {
        self.version = version
        self.timebase = timebase
        self.stage = stage
        self.actions = actions
    }

    public struct Stage: Codable, Sendable {
        /// "16:9" or "9:16". Missing values preserve the editor setting.
        public let aspect: String?
        /// "dark", "black" or "light".
        public let background: String?
        public let padding: Double?

        public init(aspect: String?, background: String?, padding: Double?) {
            self.aspect = aspect
            self.background = background
            self.padding = padding
        }
    }

    public struct Action: Codable, Sendable {
        public let id: String
        public let type: String
        /// One descriptive camera shot or one exact manually authored keyframe.
        public let start: Double?
        public let end: Double?
        public let time: Double?
        public let target: Target
        public let scale: Double
        public let transition: Transition?

        public init(id: String, type: String, start: Double? = nil,
                    end: Double? = nil, time: Double? = nil,
                    target: Target, scale: Double,
                    transition: Transition? = nil) {
            self.id = id
            self.type = type
            self.start = start
            self.end = end
            self.time = time
            self.target = target
            self.scale = scale
            self.transition = transition
        }
    }

    public struct Target: Codable, Sendable {
        /// Normalized coordinates in recorded screen space; origin top-left.
        public let x: Double
        public let y: Double

        public init(x: Double, y: Double) {
            self.x = x
            self.y = y
        }
    }

    public struct Transition: Codable, Sendable {
        /// Durations (seconds) for camera arrival and departure.
        public let `in`: Double
        public let out: Double

        public init(in inDuration: Double, out: Double) {
            self.in = inDuration
            self.out = out
        }
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
            guard let type = action["type"] as? String else {
                throw CineoInstructionError.invalid("\(prefix): type obbligatorio.")
            }
            switch type {
            case "camera.zoom":
                try fields(action, allowed: ["id", "type", "start", "end", "target", "scale", "transition"], at: prefix)
                guard let transition = action["transition"] as? [String: Any] else {
                    throw CineoInstructionError.invalid("\(prefix): transition obbligatorio per camera.zoom.")
                }
                try fields(transition, allowed: ["in", "out"], at: "\(prefix).transition")
            case "camera.keyframe":
                try fields(action, allowed: ["id", "type", "time", "target", "scale"], at: prefix)
            default:
                throw CineoInstructionError.invalid("Azione non supportata: \(type).")
            }
            guard let target = action["target"] as? [String: Any] else {
                throw CineoInstructionError.invalid("\(prefix): target obbligatorio.")
            }
            try fields(target, allowed: ["x", "y"], at: "\(prefix).target")
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
        // A descriptive zoom action creates four keyframes; an exact keyframe
        // action represents manual edits 1:1. Mixing both in v1 could yield
        // ambiguous time ordering, so reject it explicitly.
        let kinds = Set(actions.map(\.type))
        guard kinds.count <= 1 else {
            throw CineoInstructionError.invalid("Non mescolare camera.zoom e camera.keyframe nello stesso documento v1.")
        }
        let sorted = actions.sorted {
            ($0.time ?? $0.start ?? .infinity) < ($1.time ?? $1.start ?? .infinity)
        }
        var result: [CineoCameraKeyframe] = []
        var seenIDs = Set<String>()
        var lastEnd = -Double.infinity
        var lastTime = -Double.infinity
        let validID = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_-")
        for action in sorted {
            guard !action.id.isEmpty, action.id.count <= 80,
                  action.id.unicodeScalars.allSatisfy({ validID.contains($0) }),
                  seenIDs.insert(action.id).inserted else {
                throw CineoInstructionError.invalid("ID di azione duplicato o non valido: \(action.id).")
            }
            guard action.target.x.isFinite, (0...1).contains(action.target.x),
                  action.target.y.isFinite, (0...1).contains(action.target.y),
                  action.scale.isFinite else {
                throw CineoInstructionError.invalid("Azione \(action.id): coordinate o zoom non validi.")
            }

            if action.type == "camera.keyframe" {
                guard let time = action.time, action.start == nil,
                      action.end == nil, action.transition == nil,
                      time.isFinite, time >= 0, time <= duration,
                      time > lastTime, (1...3).contains(action.scale) else {
                    throw CineoInstructionError.invalid("Keyframe \(action.id): time deve crescere strettamente ed essere nella durata; scale 1…3.")
                }
                lastTime = time
                result.append(.init(time: time, zoom: action.scale,
                                    focusX: action.target.x, focusY: action.target.y))
            } else if action.type == "camera.zoom" {
                guard let start = action.start, let end = action.end,
                      let transition = action.transition, action.time == nil,
                      start.isFinite, end.isFinite,
                      start >= 0, end <= duration, end > start,
                      start > lastEnd,
                      (1.01...2.5).contains(action.scale),
                      transition.in.isFinite, transition.out.isFinite,
                      transition.in >= 0.05, transition.out >= 0.05,
                      start + transition.in + 0.05 <= end - transition.out else {
                    throw CineoInstructionError.invalid("Zoom \(action.id): intervallo, scala o transizioni non validi / sovrapposti.")
                }
                lastEnd = end
                result.append(.init(time: start, zoom: 1, focusX: 0.5, focusY: 0.5))
                result.append(.init(time: start + transition.in, zoom: action.scale,
                                    focusX: action.target.x, focusY: action.target.y))
                result.append(.init(time: end - transition.out, zoom: action.scale,
                                    focusX: action.target.x, focusY: action.target.y))
                result.append(.init(time: end, zoom: 1, focusX: 0.5, focusY: 0.5))
            } else {
                throw CineoInstructionError.invalid("Azione non supportata: \(action.type).")
            }
        }
        plan.camera = result
        try plan.validate()
        return plan
    }


    /// Show the *actual* current scene as importable JSON, without guessing
    /// semantic zoom boundaries from arbitrary manual camera animations.
    /// Validate by recompiling so that a visible "equivalent" is guaranteed
    /// to reproduce the same scene on import.
    public static func equivalentJSON(for plan: CineoScenePlan, duration: Double) throws -> String {
        try plan.validate()
        guard duration.isFinite, duration > 0, plan.camera.count <= 200 else {
            throw CineoInstructionError.invalid("Esportazione JSON: durata non valida o più di 200 keyframe.")
        }
        let aspect: String
        switch (plan.outputWidth, plan.outputHeight) {
        case (1920, 1080): aspect = "16:9"
        case (1080, 1920): aspect = "9:16"
        default:
            throw CineoInstructionError.invalid("La composizione attuale non corrisponde a un canvas 16:9 / 9:16 supportato.")
        }
        let background: String
        switch plan.background {
        case CineoRGB(red: 0.09, green: 0.12, blue: 0.19): background = "dark"
        case CineoRGB(red: 0.015, green: 0.017, blue: 0.025): background = "black"
        case CineoRGB(red: 0.91, green: 0.93, blue: 0.97): background = "light"
        default:
            throw CineoInstructionError.invalid("Il colore personalizzato del progetto non è rappresentabile nei preset JSON v1.")
        }
        let actions: [Action] = try plan.camera.enumerated().map { index, keyframe in
            guard keyframe.time <= duration else {
                throw CineoInstructionError.invalid("Keyframe oltre la durata del video.")
            }
            return Action(id: "keyframe-\(index + 1)", type: "camera.keyframe",
                          time: keyframe.time,
                          target: Target(x: keyframe.focusX, y: keyframe.focusY),
                          scale: keyframe.zoom)
        }
        let document = CineoInstructionDocument(
            stage: Stage(aspect: aspect, background: background, padding: plan.paddingFraction),
            actions: actions
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        let data = try encoder.encode(document)
        let reconstructed = try decode(data).compile(duration: duration, over: plan)
        guard reconstructed == plan else {
            throw CineoInstructionError.invalid("Round-trip del piano non equivalente: esportazione annullata.")
        }
        return String(decoding: data, as: UTF8.self)
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
