import Foundation
import AVFoundation
import CineoMusic

/// Adds imported/generated music and any original narration to an already
/// rendered Cineo video. Never changes the original recording or rendered input.
enum CineoAudioMuxer {
    static func mux(video: URL, original: URL, music: URL?,
                    settings: CineoMusicSettings?, destination: URL) async throws {
        let videoAsset = AVURLAsset(url: video)
        let vTracks = try await videoAsset.loadTracks(withMediaType: .video)
        guard let videoTrack = vTracks.first else { throw CineoMusicError.invalid("Video renderizzato senza traccia video.") }
        let duration = try await videoAsset.load(.duration)
        guard duration.isNumeric, duration.seconds > 0 else {
            throw CineoMusicError.invalid("Durata video non valida.")
        }
        let composition = AVMutableComposition()
        guard let composedVideo = composition.addMutableTrack(withMediaType: .video,
                                                     preferredTrackID: kCMPersistentTrackID_Invalid) else {
            throw CineoMusicError.invalid("Impossibile creare la composizione video.")
        }
        try composedVideo.insertTimeRange(CMTimeRange(start: .zero, duration: duration),
                                          of: videoTrack, at: .zero)
        composedVideo.preferredTransform = try await videoTrack.load(.preferredTransform)

        var parameters: [AVMutableAudioMixInputParameters] = []
        let narrationAsset = AVURLAsset(url: original)
        if let narration = try await narrationAsset.loadTracks(withMediaType: .audio).first,
           let audioTrack = composition.addMutableTrack(withMediaType: .audio,
                                                   preferredTrackID: kCMPersistentTrackID_Invalid) {
            let narrationDuration = (try await narration.load(.timeRange)).duration
            let length = CMTimeCompare(narrationDuration, duration) < 0 ? narrationDuration : duration
            if length.isNumeric && length.seconds > 0 {
                try audioTrack.insertTimeRange(CMTimeRange(start: .zero, duration: length),
                                               of: narration, at: .zero)
                let p = AVMutableAudioMixInputParameters(track: audioTrack)
                p.setVolume(1, at: .zero)
                parameters.append(p)
            }
        }

        if let music, let settings {
            try settings.validate(videoDuration: duration.seconds)
            let source = AVURLAsset(url: music)
            guard let sourceTrack = try await source.loadTracks(withMediaType: .audio).first else {
                throw CineoMusicError.invalid("La traccia musicale non contiene audio.")
            }
            guard let target = composition.addMutableTrack(withMediaType: .audio,
                                                    preferredTrackID: kCMPersistentTrackID_Invalid) else {
                throw CineoMusicError.invalid("Impossibile aggiungere la traccia musicale.")
            }
            let actualMusicDuration = try await source.load(.duration)
            let available = max(0, duration.seconds - settings.offset)
            let length = min(available, settings.duration, actualMusicDuration.seconds)
            guard length.isFinite, length > 0.02 else {
                throw CineoMusicError.invalid("Audio musicale troppo corto per il video.")
            }
            let start = CMTime(seconds: settings.offset, preferredTimescale: 600)
            let range = CMTimeRange(start: .zero,
                                    duration: CMTime(seconds: length, preferredTimescale: 600))
            try target.insertTimeRange(range, of: sourceTrack, at: start)
            let p = AVMutableAudioMixInputParameters(track: target)
            let inSeconds = min(settings.fadeIn, length / 2)
            let outSeconds = min(settings.fadeOut, length / 2)
            p.setVolume(inSeconds > 0 ? 0 : Float(settings.volume), at: start)
            if inSeconds > 0 {
                p.setVolumeRamp(fromStartVolume: 0, toEndVolume: Float(settings.volume),
                                timeRange: CMTimeRange(start: start,
                                    duration: CMTime(seconds: inSeconds, preferredTimescale: 600)))
            }
            let endStart = length - outSeconds
            if outSeconds > 0 {
                p.setVolumeRamp(fromStartVolume: Float(settings.volume), toEndVolume: 0,
                                timeRange: CMTimeRange(
                                    start: CMTimeAdd(start, CMTime(seconds: endStart, preferredTimescale: 600)),
                                    duration: CMTime(seconds: outSeconds, preferredTimescale: 600)))
            }
            parameters.append(p)
        }

        guard !parameters.isEmpty else {
            throw CineoMusicError.invalid("Non ci sono tracce audio da aggiungere.")
        }
        let mix = AVMutableAudioMix()
        mix.inputParameters = parameters
        guard let exporter = AVAssetExportSession(asset: composition,
                                                  presetName: AVAssetExportPresetHighestQuality) else {
            throw CineoMusicError.invalid("Impossibile creare l'exporter audio/video.")
        }
        exporter.audioMix = mix
        let temporary = destination.deletingLastPathComponent()
            .appendingPathComponent("." + UUID().uuidString + ".mp4")
        defer { try? FileManager.default.removeItem(at: temporary) }
        try await exporter.export(to: temporary, as: .mp4)
        let verified = AVURLAsset(url: temporary)
        guard !(try await verified.loadTracks(withMediaType: .audio)).isEmpty,
              !(try await verified.loadTracks(withMediaType: .video)).isEmpty else {
            throw CineoMusicError.invalid("MP4 esportato senza video o audio.")
        }
        guard !FileManager.default.fileExists(atPath: destination.path) else {
            throw CineoMusicError.invalid("Destinazione MP4 già esistente.")
        }
        try FileManager.default.moveItem(at: temporary, to: destination)
    }
}
