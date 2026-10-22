import Foundation

/// A non-destructive, ordered edit decision list for ONE original source.
/// Source timestamps never change. Output time is the sum of retained spans.
/// Every downstream component (renderer, narration, click events and keyframes)
/// must apply this identical mapper before trim controls are exposed in Studio.
public struct CineoCutList: Codable, Equatable, Sendable {
    public struct Span: Codable, Equatable, Sendable {
        public var start: Double
        public var end: Double
        public init(start: Double, end: Double) { self.start = start; self.end = end }
        public var duration: Double { end - start }
    }

    public let sourceDuration: Double
    public private(set) var retained: [Span]
    public static let minimumSpan = 0.1

    public init(sourceDuration: Double, retained: [Span]? = nil) throws {
        self.sourceDuration = sourceDuration
        self.retained = retained ?? [Span(start: 0, end: sourceDuration)]
        try validate()
    }

    public func validate() throws {
        guard sourceDuration.isFinite && sourceDuration >= Self.minimumSpan,
              !retained.isEmpty && retained.count <= 10_000 else {
            throw CineoCutError.invalidPlan
        }
        var previousEnd = 0.0
        for (index, span) in retained.enumerated() {
            guard span.start.isFinite, span.end.isFinite,
                  span.start >= 0, span.end <= sourceDuration,
                  span.duration >= Self.minimumSpan - 1e-9,
                  (index == 0 || span.start >= previousEnd) else {
                throw CineoCutError.invalidPlan
            }
            previousEnd = span.end
        }
    }

    public var outputDuration: Double { retained.reduce(0) { $0 + $1.duration } }

    /// Exact source media position in the cut timeline; a cut boundary is
    /// mapped to the following retained source span, not removed frames.
    public func sourceTime(at outputSeconds: Double) -> Double? {
        guard outputSeconds.isFinite, outputSeconds >= 0,
              outputSeconds < outputDuration else { return nil }
        var elapsed = 0.0
        for span in retained {
            let end = elapsed + span.duration
            if outputSeconds < end {
                return span.start + (outputSeconds - elapsed)
            }
            elapsed = end
        }
        return nil
    }

    /// Map a source moment back to the edited timeline. Removed material
    /// has no output time, so never invent a timestamp for rejected clicks.
    public func outputTime(forSourceSeconds sourceSeconds: Double) -> Double? {
        guard sourceSeconds.isFinite, sourceSeconds >= 0 else { return nil }
        var elapsed = 0.0
        for span in retained {
            if sourceSeconds >= span.start && sourceSeconds < span.end {
                return elapsed + sourceSeconds - span.start
            }
            elapsed += span.duration
        }
        return nil
    }

    /// Remove [start,end) in the CURRENT edited output timeline. This
    /// supports consecutive cuts without confusing output/source clocks.
    public func removingOutputRange(start: Double, end: Double) throws -> CineoCutList {
        guard start.isFinite, end.isFinite,
              start >= 0, start < end, end <= outputDuration else {
            throw CineoCutError.invalidRange
        }
        var survivors: [Span] = []
        var cursor = 0.0
        for span in retained {
            let next = cursor + span.duration
            let removedStart = max(cursor, start)
            let removedEnd = min(next, end)
            if removedStart >= removedEnd {
                survivors.append(span)
            } else {
                let before = removedStart - cursor
                let after = next - removedEnd
                if before >= Self.minimumSpan {
                    survivors.append(Span(start: span.start, end: span.start + before))
                }
                if after >= Self.minimumSpan {
                    survivors.append(Span(start: span.end - after, end: span.end))
                }
            }
            cursor = next
        }
        guard !survivors.isEmpty else { throw CineoCutError.emptyTimeline }
        return try CineoCutList(sourceDuration: sourceDuration, retained: survivors)
    }

    /// Intersect source-timed narration/ducking ranges with kept spans and
    /// return their intervals in the *edited output* clock.
    public func outputRanges(overlappingSourceStart start: Double,
                             end: Double) -> [Span] {
        guard start.isFinite, end.isFinite, start >= 0, end > start else { return [] }
        var results: [Span] = []
        var outputCursor = 0.0
        for span in retained {
            let a = max(start, span.start), b = min(end, span.end)
            if b > a {
                results.append(Span(start: outputCursor + (a - span.start),
                                    end: outputCursor + (b - span.start)))
            }
            outputCursor += span.duration
        }
        return results
    }

    /// Next retained source position when playback reaches a removed region.
    /// Nil means the edited timeline has ended.
    public func nextRetainedSourceTime(after sourceSeconds: Double) -> Double? {
        guard sourceSeconds.isFinite else { return nil }
        return retained.first(where: { $0.end > sourceSeconds })?.start
    }

    /// Remove [start,end) in SOURCE time; preserve media and all other spans.
    /// This is deliberately NOT allowed to delete the entire recording.
    public func removingSourceRange(start: Double, end: Double) throws -> CineoCutList {
        guard start.isFinite, end.isFinite, start >= 0,
              start < end, end <= sourceDuration else {
            throw CineoCutError.invalidRange
        }
        var result: [Span] = []
        for span in retained {
            if span.end <= start || span.start >= end {
                result.append(span)
            } else {
                if start - span.start >= Self.minimumSpan {
                    result.append(Span(start: span.start, end: start))
                }
                if span.end - end >= Self.minimumSpan {
                    result.append(Span(start: end, end: span.end))
                }
            }
        }
        guard !result.isEmpty else { throw CineoCutError.emptyTimeline }
        return try CineoCutList(sourceDuration: sourceDuration, retained: result)
    }
}

public enum CineoCutError: Error, Equatable, Sendable {
    case invalidRange, invalidPlan, emptyTimeline
}
