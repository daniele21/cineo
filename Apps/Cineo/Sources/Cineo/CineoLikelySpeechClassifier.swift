import Foundation
import AVFoundation
import SoundAnalysis
import CineoMusic

/// Apple's built-in local sound classifier, not remote dictation. No transcript
/// is recorded or stored. Confidence is probabilistic and not verified VAD.
enum CineoLikelySpeechClassifier {
    static func ranges(url: URL, confidence: Double = 0.35)
        async throws -> [CineoAudioActivityRange] {
        guard url.isFileURL, confidence.isFinite, (0...1).contains(confidence) else {
            throw CineoMusicError.invalid("Sorgente o soglia del classificatore non validi.")
        }
        let request = try SNClassifySoundRequest(classifierIdentifier: .version1)
        let labels = request.knownClassifications.filter {
            let value = $0.lowercased()
            return value == "speech" || value == "conversation"
                   || value.contains("human speech")
        }
        guard !labels.isEmpty else {
            throw CineoMusicError.unavailable(
                "Il modello SoundAnalysis di questo macOS non espone un'etichetta per il parlato.")
        }
        // OS classifier windows are coarse; intersection with local RMS
        // preserves actual silence gaps and limits non-speech activation.
        let observer = CineoSpeechClassificationObserver(
            labels: labels, minimumConfidence: confidence)
        let analyzer = try SNAudioFileAnalyzer(url: url)
        try analyzer.add(request, withObserver: observer)
        let completed = await analyzer.analyze()
        try Task.checkCancellation()
        guard completed else {
            throw CineoMusicError.unavailable("Classificazione audio interrotta prima del termine.")
        }
        if let error = observer.failure {
            throw CineoMusicError.unavailable(
                "Analisi parlato locale non disponibile: " + error)
        }
        return observer.sortedRanges
    }
}

private final class CineoSpeechClassificationObserver: NSObject, SNResultsObserving,
                                                        @unchecked Sendable {
    let labels: [String]
    let minimumConfidence: Double
    private let lock = NSLock()
    private var matches: [CineoAudioActivityRange] = []
    private var lastFailure: String?

    init(labels: [String], minimumConfidence: Double) {
        self.labels = labels
        self.minimumConfidence = minimumConfidence
    }

    func request(_ request: SNRequest, didProduce result: SNResult) {
        guard let classification = result as? SNClassificationResult else { return }
        let accepted = labels.contains { label in
            (classification.classification(forIdentifier: label)?.confidence ?? 0)
                >= minimumConfidence
        }
        guard accepted else { return }
        let start = classification.timeRange.start.seconds
        let end = CMTimeRangeGetEnd(classification.timeRange).seconds
        guard start.isFinite, end.isFinite, end > start else { return }
        lock.lock()
        matches.append(.init(start: max(0, start), end: end))
        lock.unlock()
    }

    func request(_ request: SNRequest, didFailWithError error: Error) {
        lock.lock()
        lastFailure = error.localizedDescription
        lock.unlock()
    }

    func requestDidComplete(_ request: SNRequest) { }

    var failure: String? {
        lock.lock()
        defer { lock.unlock() }
        return lastFailure
    }

    var sortedRanges: [CineoAudioActivityRange] {
        lock.lock()
        let data = matches
        lock.unlock()
        let ordered = data.sorted { $0.start < $1.start }
        var result: [CineoAudioActivityRange] = []
        for item in ordered {
            if let previous = result.last, item.start <= previous.end + 0.1 {
                result[result.count - 1] = .init(
                    start: previous.start, end: max(previous.end, item.end))
            } else { result.append(item) }
        }
        return result
    }
}
