import Foundation
import AVFoundation
import CineoMusic

/// All three time domains (video, trimmed/looped source, original audio)
/// meet in one non-destructive, frozen export composition.
enum CineoAudioMuxer {
    static func mux(video: URL, original: URL, music: URL?,
                    settings: CineoMusicSettings?, clip: CineoMusicClip = .init(),
                    ducking: CineoDuckingSettings = .init(), destination: URL) async throws {
        try ducking.validate()
        let videoAsset = AVURLAsset(url: video)
        let tracks = try await videoAsset.loadTracks(withMediaType: .video)
        guard let videoTrack = tracks.first else {
            throw CineoMusicError.invalid("Video renderizzato senza traccia video.")
        }
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
        let originalAudio = try await narrationAsset.loadTracks(withMediaType: .audio).first
        if let narration = originalAudio,
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
        // Original media may contain system sounds, voice, or both. The UI
        // explicitly labels this as original-audio ducking, not voice AI.
        let activity: [CineoAudioActivity]
        if music != nil && ducking.enabled && originalAudio != nil {
            activity = try await CineoMusicAudioAnalyzer.activity(
                url: original, thresholdDB: ducking.thresholdDB)
        } else { activity = [] }

        if let music, let settings {
            try settings.validate(videoDuration: duration.seconds)
            let source = AVURLAsset(url: music)
            guard let sourceTrack = try await source.loadTracks(withMediaType: .audio).first else {
                throw CineoMusicError.invalid("La traccia musicale non contiene audio.")
            }
            let musicDuration = try await source.load(.duration)
            let segments = try clip.arrangedSegments(sourceDuration: musicDuration.seconds,
                videoDuration: duration.seconds, offset: settings.offset)
            guard let last = segments.last else {
                throw CineoMusicError.invalid("La traccia musicale non entra nella durata del video.")
            }
            let length = last.timelineStart + last.duration - settings.offset
            let fadeIn = min(settings.fadeIn, length / 2)
            let fadeOut = min(settings.fadeOut, length / 2)
            let lanes = Set(segments.map(\.lane)).sorted()
            for lane in lanes {
                guard let target = composition.addMutableTrack(withMediaType: .audio,
                                  preferredTrackID: kCMPersistentTrackID_Invalid) else {
                    throw CineoMusicError.invalid("Impossibile aggiungere il canale musicale.")
                }
                let p = AVMutableAudioMixInputParameters(track: target)
                p.setVolume(0, at: .zero)
                for segment in segments where segment.lane == lane {
                    try Task.checkCancellation()
                    let sourceRange = CMTimeRange(
                        start: CMTime(seconds: segment.sourceStart, preferredTimescale: 600),
                        duration: CMTime(seconds: segment.duration, preferredTimescale: 600))
                    try target.insertTimeRange(sourceRange, of: sourceTrack,
                        at: CMTime(seconds: segment.timelineStart, preferredTimescale: 600))

                    // Each lane has its own crossfade; ducking and clip fades
                    // are applied at absolute video time, not source time.
                    let segmentStart = segment.timelineStart
                    let segmentEnd = segmentStart + segment.duration
                    let automation = CineoAudioDynamics.automation(
                        start: segmentStart, end: segmentEnd,
                        settings: ducking, activity: activity) { time in
                        let local = time - settings.offset
                        let elapsed = time - segmentStart
                        let outerIn = fadeIn > 0 ? min(1, local / fadeIn) : 1
                        let outerOut = fadeOut > 0 ? min(1, (length - local) / fadeOut) : 1
                        let seamIn = segment.fadeIn > 0 ? min(1, elapsed / segment.fadeIn) : 1
                        let seamOut = segment.fadeOut > 0 ?
                            min(1, (segment.duration - elapsed) / segment.fadeOut) : 1
                        return settings.volume * max(0, min(outerIn, outerOut)) *
                            seamIn * seamOut *
                            CineoAudioDynamics.gain(at: time, activity: activity, settings: ducking)
                    }
                    if let first = automation.first {
                        p.setVolume(Float(first.gain),
                                    at: CMTime(seconds: first.time, preferredTimescale: 600))
                    }
                    for (a, b) in zip(automation, automation.dropFirst()) {
                        guard b.time > a.time + 0.00001 else { continue }
                        p.setVolumeRamp(
                            fromStartVolume: Float(a.gain), toEndVolume: Float(b.gain),
                            timeRange: CMTimeRange(
                                start: CMTime(seconds: a.time, preferredTimescale: 600),
                                duration: CMTime(seconds: b.time - a.time, preferredTimescale: 600)))
                    }
                }
                parameters.append(p)
            }
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
