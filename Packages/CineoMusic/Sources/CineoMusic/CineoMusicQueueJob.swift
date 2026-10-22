import Foundation

/// Checkpoint is saved synchronously by the app after ACE-Step acknowledges
/// a remote job. A future app session can poll the same server job ID.
public struct CineoACEJobCheckpoint: Codable, Equatable, Sendable {
    public enum Stage: String, Codable, Sendable {
        case lm, synth, repaint
    }
    public let stage: Stage
    public let remoteID: String

    public init(stage: Stage, remoteID: String) throws {
        guard !remoteID.isEmpty, remoteID.count < 100,
              remoteID.utf8.allSatisfy({ b in
                  (b >= 48 && b <= 57) || (b >= 65 && b <= 90) ||
                  (b >= 97 && b <= 122) || b == 45 || b == 95
              }) else { throw CineoMusicError.invalid("ID job ACE-Step non valido.") }
        self.stage = stage
        self.remoteID = remoteID
    }
}

/// Persisted jobs survive dismissal of the Music Director sheet, switching
/// videos and ordinary app relaunches. Completing a job never overwrites an
/// existing soundtrack: the user explicitly attaches the result later.
public struct CineoMusicQueueJob: Codable, Equatable, Identifiable, Sendable {
    public enum Kind: String, Codable, Sendable {
        case generation, repaint
    }
    public enum Phase: String, Codable, Sendable {
        case queued, running, ready, failed, cancelled, interrupted
        public var isTerminal: Bool {
            self == .ready || self == .failed || self == .cancelled
        }
    }
    public let id: UUID
    public let kind: Kind
    public var originVideoPath: String
    public let title: String
    public let settings: CineoMusicSettings
    public let repaint: CineoACERepaintRequest?
    public let sourceAudioPath: String?
    public let destinationPath: String
    public let createdAt: Date
    public var phase: Phase
    public var checkpoint: CineoACEJobCheckpoint?
    public var status: String

    public init(id: UUID = UUID(), kind: Kind, originVideoPath: String,
                title: String, settings: CineoMusicSettings,
                repaint: CineoACERepaintRequest? = nil,
                sourceAudioPath: String? = nil, destinationPath: String,
                createdAt: Date = Date()) throws {
        guard !originVideoPath.isEmpty, originVideoPath.utf8.count < 4096,
              !destinationPath.isEmpty, destinationPath.utf8.count < 4096,
              title.utf8.count <= 256 else {
            throw CineoMusicError.invalid("Identità job o destinazione non valida.")
        }
        if kind == .repaint {
            guard let repaint, let sourceAudioPath, !sourceAudioPath.isEmpty else {
                throw CineoMusicError.invalid("Il job repaint richiede un audio originale.")
            }
            try repaint.validate()
        } else {
            guard repaint == nil, sourceAudioPath == nil else {
                throw CineoMusicError.invalid("Job di generazione non valido.")
            }
        }
        try settings.validate()
        self.id = id
        self.kind = kind
        self.originVideoPath = originVideoPath
        self.title = title
        self.settings = settings
        self.repaint = repaint
        self.sourceAudioPath = sourceAudioPath
        self.destinationPath = destinationPath
        self.createdAt = createdAt
        self.phase = .queued
        self.checkpoint = nil
        self.status = "In coda"
    }

    /// A remote job ID is only meaningful on its original live server.
    /// Do not silently resubmit or poll it across a Cineo application restart.
    public mutating func invalidateUnverifiedRemoteCheckpoint() {
        guard checkpoint != nil else { return }
        if phase == .queued || phase == .interrupted {
            phase = .interrupted
            checkpoint = nil
            status = "Server ACE-Step precedente non verificabile. Riprova il job manualmente."
        }
    }

    public mutating func recoverAfterAppRestart(outputExists: Bool) {
        if phase == .running && outputExists {
            phase = .ready
            checkpoint = nil
            status = "Traccia generata recuperata dopo la riapertura."
        } else if phase == .running {
            if checkpoint != nil {
                status = "Ripresa monitoraggio ACE-Step dopo riapertura…"
                phase = .queued
            } else {
                phase = .interrupted
                status = "Invio al server interrotto prima di salvare l'ID: riprova manualmente."
            }
        } else if phase == .ready && !outputExists {
            phase = .failed
            status = "File generato non più disponibile; sorgenti preservate."
        }
    }
}
