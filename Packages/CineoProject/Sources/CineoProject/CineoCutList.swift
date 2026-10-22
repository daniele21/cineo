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
