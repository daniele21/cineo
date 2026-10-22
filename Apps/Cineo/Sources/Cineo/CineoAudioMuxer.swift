import Foundation
import AVFoundation
import CineoMusic

/// Adds imported/generated music and any original narration to an already
/// rendered Cineo video. Never changes the original recording or rendered input.
enum CineoAudioMuxer {
    static func mux(video: URL, original: URL, music: URL?,
                    settings: CineoMusicSettings?, clip: CineoMusicClip = .init(),
                    ducking: CineoDuckingSettings = .init(),
                    duckingRanges: [CineoAudioActivityRange] = [],
                    destination: URL) async throws {
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
            try ducking.validate()
            let source = AVURLAsset(url: music)
            guard let sourceTrack = try await source.loadTracks(withMediaType: .audio).first else {
                throw CineoMusicError.invalid("La traccia musicale non contiene audio.")
            }
            let actualMusicDuration = try await source.load(.duration)
            let segments = try clip.segments(sourceDuration: actualMusicDuration.seconds,
                                             videoDuration: duration.seconds, offset: settings.offset)
            guard let last = segments.last else {
                throw CineoMusicError.invalid("Audio musicale troppo corto per il video.")
            }
            let clipStart = settings.offset
            let clipEnd = last.timelineStart + last.duration
            // Interleaving A/B ensures overlapping loop passes never share
            // the same mutable composition track (which forbids overlaps).
            let trackCount = clip.loop && clip.loopCrossfade > 0 ? 2 : 1
            var musicTracks: [AVMutableCompositionTrack] = []
            for _ in 0..<trackCount {
                guard let target = composition.addMutableTrack(withMediaType: .audio,
                                      preferredTrackID: kCMPersistentTrackID_Invalid) else {
                    throw CineoMusicError.invalid("Impossibile aggiungere la traccia musicale.")
                }
                musicTracks.append(target)
            }
            for (index, part) in segments.enumerated() {
                try Task.checkCancellation()
                let sourceRange = CMTimeRange(
                    start: CMTime(seconds: part.sourceStart, preferredTimescale: 6000),
                    duration: CMTime(seconds: part.duration, preferredTimescale: 6000))
                try musicTracks[index % trackCount].insertTimeRange(
                    sourceRange, of: sourceTrack,
                    at: CMTime(seconds: part.timelineStart, preferredTimescale: 6000))
            }
            let fadeIn = min(settings.fadeIn, (clipEnd - clipStart) / 2)
            let fadeOut = min(settings.fadeOut, (clipEnd - clipStart) / 2)
            let overlap = clip.loop ? clip.loopCrossfade : 0

            // Sample a deterministic product of global fade, optional audio
            // ducking and per-repeat crossfade. A 100ms bound plus all explicit
            // transition boundaries avoids discontinuities in AVAudioMix.
            var boundaries: [Double] = [
                clipStart, clipEnd, clipStart + fadeIn, clipEnd - fadeOut
            ]
            for (index, part) in segments.enumerated() {
                let end = part.timelineStart + part.duration
                boundaries.append(contentsOf: [part.timelineStart, end])
                if overlap > 0 {
                    if index > 0 {
                        boundaries.append(contentsOf: [part.timelineStart + overlap / 2,
                                                       part.timelineStart + overlap])
                    }
                    if index + 1 < segments.count {
                        boundaries.append(contentsOf: [end - overlap, end - overlap / 2])
                    }
                }
            }
            if ducking.enabled {
                for range in duckingRanges {
                    boundaries.append(contentsOf: [range.start - ducking.attack,
                                                   range.start, range.end,
                                                   range.end + ducking.release])
                }
            }
            let steps = Int(ceil((clipEnd - clipStart) / 0.1))
            if steps > 0 {
                for i in 0...steps {
                    boundaries.append(clipStart + (clipEnd - clipStart) * Double(i) / Double(steps))
                }
            }
            let times = Array(Set(boundaries.filter {
                $0.isFinite && $0 >= clipStart && $0 <= clipEnd
            })).sorted()

            for trackIndex in musicTracks.indices {
                let p = AVMutableAudioMixInputParameters(track: musicTracks[trackIndex])
                func gain(at time: Double) -> Float {
                    let elapsed = time - clipStart
                    let total = clipEnd - clipStart
                    let envelopeIn = fadeIn > 0 ? min(1, max(0, elapsed / fadeIn)) : 1
                    let envelopeOut = fadeOut > 0
                        ? min(1, max(0, (total - elapsed) / fadeOut)) : 1
                    let duck = ducking.gain(at: time, activeRanges: duckingRanges)
                    var layerGain = 0.0
                    for (index, part) in segments.enumerated()
                        where index % trackCount == trackIndex {
                        let segmentEnd = part.timelineStart + part.duration
                        guard time >= part.timelineStart, time <= segmentEnd else { continue }
                        let local = time - part.timelineStart
                        let fadeUp = index > 0 && overlap > 0
                            ? min(1, max(0, local / overlap)) : 1
                        let hasNext = index + 1 < segments.count
                        let fadeDown = hasNext && overlap > 0
                            ? min(1, max(0, (segmentEnd - time) / overlap)) : 1
                        layerGain = max(layerGain, min(fadeUp, fadeDown))
                    }
                    return Float(max(0, min(1, settings.volume *
                                envelopeIn * envelopeOut * duck * layerGain)))
                }
                if let first = times.first {
                    p.setVolume(gain(at: first),
                                at: CMTime(seconds: first, preferredTimescale: 6000))
                }
                for i in 1..<times.count {
                    let t0 = times[i - 1], t1 = times[i]
                    let range = CMTimeRange(
                        start: CMTime(seconds: t0, preferredTimescale: 6000),
                        duration: CMTime(seconds: t1 - t0, preferredTimescale: 6000))
                    if range.duration.value > 0 {
                        p.setVolumeRamp(fromStartVolume: gain(at: t0),
                                        toEndVolume: gain(at: t1), timeRange: range)
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
