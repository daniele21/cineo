import Foundation

/// Treats *any significant original-audio activity* as a signal to lower
/// the soundtrack. It is not speech recognition or speaker diarization.
public struct CineoDuckingSettings: Codable, Equatable, Sendable {
    public var enabled: Bool
    public var quietVolume: Double
    public var thresholdDB: Double
    public var attack: Double
    public var release: Double

    public init(enabled: Bool = false, quietVolume: Double = 0.28,
                thresholdDB: Double = -35, attack: Double = 0.12,
                release: Double = 0.45) {
        self.enabled = enabled
        self.quietVolume = quietVolume
        self.thresholdDB = thresholdDB
        self.attack = attack
        self.release = release
    }

    public func validate() throws {
        guard quietVolume.isFinite, (0...1).contains(quietVolume),
              thresholdDB.isFinite, (-80 ... -5).contains(thresholdDB),
              attack.isFinite, (0.01...2).contains(attack),
              release.isFinite, (0.02...5).contains(release) else {
            throw CineoMusicError.invalid("Ducking: soglia, volume o tempi non validi.")
        }
    }
}

public struct CineoAudioActivity: Codable, Equatable, Sendable {
    public let start: Double
    public let end: Double

    public init(start: Double, end: Double) {
        self.start = start
        self.end = end
    }
}

public struct CineoMusicCue: Codable, Identifiable, Equatable, Sendable {
    public let id: String
    public var time: Double
    public var label: String

    public init(id: String = UUID().uuidString, time: Double, label: String = "Cue") {
        self.id = id
        self.time = time
        self.label = label
    }

    public func validate(videoDuration: Double) throws {
        guard !id.isEmpty, id.count <= 100, !label.isEmpty,
              label.count <= 60, time.isFinite, (0..<videoDuration).contains(time)
        else { throw CineoMusicError.invalid("Cue: tempo o nome non valido.") }
    }
}

public enum CineoAudioDynamics {
    /// 50ms RMS frames with 120ms minimum-active and 180ms gap-merging.
    /// This intentionally responds to original audio, not to inferred voices.
    public static func detectActivity(samples: [Float], sampleRate: Double,
                                      thresholdDB: Double = -35,
                                      frameSeconds: Double = 0.05) -> [CineoAudioActivity] {
        guard sampleRate.isFinite, sampleRate >= 8000, !samples.isEmpty,
              thresholdDB.isFinite, (-80 ... -5).contains(thresholdDB) else { return [] }
        let frame = max(1, Int(sampleRate * frameSeconds))
        let threshold = pow(10, thresholdDB / 20)
        let frameCount = (samples.count + frame - 1) / frame
        var active = [Bool](repeating: false, count: frameCount)
        for i in 0..<frameCount {
            let start = i * frame
            let end = min(samples.count, start + frame)
            var sum = 0.0
            for j in start..<end {
                let x = Double(samples[j].isFinite ? samples[j] : 0)
                sum += x * x
            }
            active[i] = sqrt(sum / Double(end - start)) > threshold
        }
        let minimum = max(1, Int(ceil(0.12 / frameSeconds)))
        let maxGap = max(0, Int(ceil(0.18 / frameSeconds)))
        var groups: [(Int, Int)] = []
        var start: Int?
        var lastOn = -1
        for i in active.indices where active[i] {
            if start == nil {
                start = i
            } else if i - lastOn - 1 > maxGap {
                groups.append((start!, lastOn + 1))
                start = i
            }
            lastOn = i
        }
        if let start { groups.append((start, lastOn + 1)) }
        return groups.filter { pair in active[pair.0..<pair.1].filter { $0 }.count >= minimum }
            .map { pair in
                CineoAudioActivity(start: Double(pair.0 * frame) / sampleRate,
                                   end: min(Double(samples.count) / sampleRate,
                                            Double(pair.1 * frame) / sampleRate))
            }
    }

    public static func gain(at time: Double, activity: [CineoAudioActivity],
                            settings: CineoDuckingSettings) -> Double {
        guard settings.enabled else { return 1 }
        var gain = 1.0
        for interval in activity {
            let level: Double
            if time < interval.start - settings.attack || time > interval.end + settings.release {
                continue
            } else if time < interval.start {
                level = 1 - (1 - settings.quietVolume) *
                    ((time - interval.start + settings.attack) / settings.attack)
            } else if time <= interval.end {
                level = settings.quietVolume
            } else {
                level = settings.quietVolume + (1 - settings.quietVolume) *
                    ((time - interval.end) / settings.release)
            }
            gain = min(gain, max(0, min(1, level)))
        }
        return gain
    }

    /// Exact piecewise-linear cue knots for one ducked source; subdivisions
    /// approximate the product of ducking, clip fade and loop crossfade.
    /// A bounded 50ms step keeps AVAudioMix ramps small even in long clips.
    public static func automation(start: Double, end: Double,
                                  settings: CineoDuckingSettings,
                                  activity: [CineoAudioActivity],
                                  evaluator: (Double) -> Double) -> [(time: Double, gain: Double)] {
        guard end > start else { return [] }
        var times: [Double] = [start, end]
        let add = { (t: Double) in max(start, min(end, t)) }
        for x in activity {
            times += [add(x.start - settings.attack), add(x.start),
                      add(x.end), add(x.end + settings.release)]
        }
        times.sort()
        var dense: [Double] = [start]
        for next in times where next > dense.last! + 0.0001 {
            var t = dense.last! + 0.05
            while t < next - 0.0001 {
                dense.append(t)
                t += 0.05
            }
            dense.append(next)
        }
        let values = dense.map { (time: $0, gain: max(0, min(1, evaluator($0)))) }
        var reduced: [(time: Double, gain: Double)] = []
        for point in values {
            reduced.append(point)
            while reduced.count >= 3 {
                let n = reduced.count
                let a = reduced[n - 3], b = reduced[n - 2], c = reduced[n - 1]
                let expected = a.gain + (c.gain - a.gain) * (b.time - a.time) / (c.time - a.time)
                if abs(expected - b.gain) <= 0.0015 {
                    reduced.remove(at: n - 2)
                } else { break }
            }
        }
        return reduced
    }
}
