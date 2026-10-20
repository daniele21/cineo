import SwiftUI
import ScreenCaptureKit
import AVFoundation
import CoreMedia
import CoreVideo
import AppKit
import OSLog
import UniformTypeIdentifiers

@main
struct CineoApp: App {
    @StateObject private var recorder = CineoScreenRecorder()
    @StateObject private var editor = CineoEditorModel()

    var body: some Scene {
        WindowGroup("Cineo") {
            Group {
                if editor.sourceURL != nil {
                    CineoManualEditorView(editor: editor) {
                        editor.close()
                    }
                } else {
                    CaptureDashboard(recorder: recorder) { url in
                        Task { await editor.open(url) }
                    }
                }
            }
        }
        .windowResizability(.contentSize)
    }
}

enum CapturePhase: String {
    case ready
    case preparing
    case recording
    case finalizing
    case verifying
    case complete
    case failed

    var isWorking: Bool {
        self == .preparing || self == .finalizing || self == .verifying
    }

    var name: String {
        switch self {
        case .ready: "Ready"
        case .preparing: "Preparing"
        case .recording: "Recording"
        case .finalizing: "Finalizing MP4"
        case .verifying: "Verifying MP4"
        case .complete: "Saved"
        case .failed: "Error"
        }
    }
}

struct CaptureLogEntry: Identifiable {
    let id = UUID()
    let date = Date()
    let level: Level
    let message: String

    enum Level {
        case info, warning, error
    }
}

private struct CaptureDashboard: View {
    @ObservedObject var recorder: CineoScreenRecorder
    let onEditVideo: (URL) -> Void

    private var buildRevision: String {
        Bundle.main.object(forInfoDictionaryKey: "CineoSourceCommit") as? String ?? "unknown"
    }

    private var timeText: String {
        let total = Int(recorder.recordedSeconds)
        return String(format: "%02d:%02d", total / 60, total % 60)
    }

    private var fileSizeText: String {
        recorder.recordedBytes > 0
            ? ByteCountFormatter.string(fromByteCount: recorder.recordedBytes, countStyle: .file)
            : "Waiting for data…"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                Image(systemName: "record.circle")
                    .font(.system(size: 32))
                VStack(alignment: .leading, spacing: 3) {
                    Text("Cineo").font(.title.bold())
                    Text("Local-first screen capture • SwiftPM + Command Line Tools")
                        .foregroundStyle(.secondary)
                    Text("Capture fix candidate • stream-stop finalization")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("SOURCE \(buildRevision) • PID \(ProcessInfo.processInfo.processIdentifier)")
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
            }
            Divider()
            Text("Capture your display to a local H.264 MP4.")
                .font(.headline)
            HStack(spacing: 12) {
                if recorder.phase == .recording {
                    Button {
                        Task { await recorder.stop() }
                    } label: {
                        Label("Stop recording", systemImage: "stop.fill")
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.red)
                } else {
                    Button {
                        Task { await recorder.start() }
                    } label: {
                        Label("Record main display", systemImage: "record.circle")
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(recorder.phase.isWorking)
                }
                Button {
                    recorder.openRecordingsFolder()
                } label: {
                    Label("Show recordings", systemImage: "folder")
                }
                if let url = recorder.lastCompletedVideo, recorder.phase == .complete {
                    Button {
                        recorder.openLastRecording()
                    } label: {
                        Label("Open MP4", systemImage: "play.rectangle")
                    }
                    .help(url.lastPathComponent)
                }
                if let url = recorder.lastCompletedVideo, recorder.phase == .complete {
                    Button {
                        onEditVideo(url)
                    } label: {
                        Label("Apri editor", systemImage: "slider.horizontal.3")
                    }
                    .buttonStyle(.borderedProminent)
                    .help("Modifica inquadratura, zoom e sfondi; il video originale resta invariato.")
                }
                Button {
                    let panel = NSOpenPanel()
                    panel.canChooseDirectories = false
                    panel.allowsMultipleSelection = false
                    panel.allowedContentTypes = [.mpeg4Movie, .movie]
                    if panel.runModal() == .OK, let url = panel.url {
                        onEditVideo(url)
                    }
                } label: {
                    Label("Modifica MP4…", systemImage: "film")
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    if recorder.phase == .recording {
                        Image(systemName: "record.circle.fill")
                            .foregroundStyle(.red)
                            .symbolEffect(.pulse)
                    } else if recorder.phase.isWorking {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Image(systemName: recorder.phase == .complete ? "checkmark.circle.fill" :
                              recorder.phase == .failed ? "exclamationmark.triangle.fill" : "info.circle")
                            .foregroundStyle(recorder.phase == .failed ? .orange : .secondary)
                    }
                    Text(recorder.phase.name)
                        .font(.headline)
                    Spacer()
                    Text(timeText)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
                Text(recorder.status)
                    .font(.callout)
                    .textSelection(.enabled)

                HStack(spacing: 20) {
                    Label("Captured: \(timeText)", systemImage: "clock")
                    Label("File: \(fileSizeText)", systemImage: "doc")
                }
                .font(.caption)
                .foregroundStyle(.secondary)

                if recorder.phase == .finalizing || recorder.phase == .verifying {
                    Text("Finalization: \(recorder.finalizationElapsedSeconds) s elapsed • waiting for system confirmation. No reliable percentage is available.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if recorder.finalizationElapsedSeconds >= 15 {
                        Text("This is taking longer than usual. The source file is not deleted. Check the activity log for errors.")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                }
                if let file = recorder.currentFilename {
                    Text(file)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .textSelection(.enabled)
                }
            }
            .padding(14)
            .background(.quaternary.opacity(0.3), in: RoundedRectangle(cornerRadius: 10))

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Label("Activity log (\(recorder.logs.count))", systemImage: "list.bullet.rectangle")
                        .font(.callout.weight(.medium))
                    Spacer()
                    Button("Copy diagnostics") {
                        recorder.copyDiagnostics()
                    }
                    .font(.caption)
                }
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 6) {
                            ForEach(recorder.logs) { entry in
                                HStack(alignment: .firstTextBaseline, spacing: 8) {
                                    Text(entry.date, style: .time)
                                        .monospacedDigit()
                                        .foregroundStyle(.secondary)
                                    Image(systemName: entry.level == .error ? "exclamationmark.circle" :
                                          entry.level == .warning ? "exclamationmark.triangle" : "checkmark.circle")
                                        .foregroundStyle(entry.level == .error ? .red : .secondary)
                                    Text(entry.message)
                                        .textSelection(.enabled)
                                }
                                .font(.caption)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .id(entry.id)
                            }
                        }
                    }
                    .frame(height: 135)
                    .onChange(of: recorder.logs.count) { _, _ in
                        if let last = recorder.logs.last {
                            proxy.scrollTo(last.id, anchor: .bottom)
                        }
                    }
                }
            }
            Text("Manual and assisted editor preview is available from Apri editor / Modifica MP4. Click-based automatic recognition is not yet available. Everything stays local.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(width: 620)
        .padding(22)
    }
}

/// Explicit observable state machine for the capture + asynchronous MP4
/// finalization lifecycle. A successful stop request is NOT success: only
/// the delegate's finish callback followed by AVFoundation validation is.
@MainActor
final class CineoScreenRecorder: NSObject, ObservableObject, SCRecordingOutputDelegate, SCStreamDelegate {
    @Published private(set) var phase: CapturePhase = .ready
    @Published private(set) var status = "Ready. No screen permissions requested."
    @Published private(set) var recordedSeconds: Double = 0
    @Published private(set) var recordedBytes: Int64 = 0
    @Published private(set) var finalizationElapsedSeconds: Int = 0
    @Published private(set) var currentFilename: String?
    @Published private(set) var lastCompletedVideo: URL?
    @Published private(set) var logs: [CaptureLogEntry] = []

    private let systemLog = Logger(subsystem: "com.daniele21.cineo.capturealpha", category: "recording")
    private var stream: SCStream?
    private var output: SCRecordingOutput?
    private var targetURL: URL?
    private var finalizationStarted: Date?
    private var monitorTask: Task<Void, Never>?

    override init() {
        super.init()
        log("Ready. Nothing is being recorded.")
        log("Build variant: stream-stop finalization (fix/screencapture-stop-finalization-race).")
        let revision = Bundle.main.object(forInfoDictionaryKey: "CineoSourceCommit") as? String ?? "unknown"
        let bundleID = Bundle.main.bundleIdentifier ?? "unknown"
        log("Runtime identity: SOURCE=\(revision) PID=\(ProcessInfo.processInfo.processIdentifier) BUNDLE=\(bundleID)")
        log("Running app location: \(Bundle.main.bundleURL.path)")
    }

    private var recordingsDirectory: URL {
        FileManager.default.urls(for: .moviesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Cineo", isDirectory: true)
    }

    private func log(_ message: String, level: CaptureLogEntry.Level = .info) {
        logs.append(CaptureLogEntry(level: level, message: message))
        if logs.count > 100 { logs.removeFirst(logs.count - 100) }
        switch level {
        case .info: systemLog.info("\(message, privacy: .private)")
        case .warning: systemLog.warning("\(message, privacy: .private)")
        case .error: systemLog.error("\(message, privacy: .private)")
        }
    }

    private func monitor() {
        monitorTask?.cancel()
        monitorTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                if let output = self.output {
                    let seconds = CMTimeGetSeconds(output.recordedDuration)
                    if seconds.isFinite && seconds >= 0 {
                        self.recordedSeconds = seconds
                    }
                    self.recordedBytes = max(0, Int64(output.recordedFileSize))
                }
                if let start = self.finalizationStarted {
                    self.finalizationElapsedSeconds = max(0, Int(Date().timeIntervalSince(start)))
                }
                if self.phase == .ready || self.phase == .complete || self.phase == .failed {
                    return
                }
                try? await Task.sleep(for: .milliseconds(500))
            }
        }
    }

    private func fail(_ message: String) {
        phase = .failed
        status = message
        log(message, level: .error)
        monitorTask?.cancel()
        monitorTask = nil
    }

    func start() async {
        guard stream == nil, output == nil, !phase.isWorking else { return }
        phase = .preparing
        status = "Checking available screens and recording permission…"
        currentFilename = nil
        lastCompletedVideo = nil
        targetURL = nil
        recordedSeconds = 0
        recordedBytes = 0
        finalizationElapsedSeconds = 0
        finalizationStarted = nil
        log("Checking Screen Recording permission and available displays.")
        monitor()
        do {
            let available = try await SCShareableContent.excludingDesktopWindows(
                false, onScreenWindowsOnly: true
            )
            guard let display = available.displays.first(where: {
                $0.displayID == CGMainDisplayID()
            }) ?? available.displays.first else {
                fail("No display found. Check Screen Recording permission in System Settings.")
                return
            }
            log("Main display selected (\(display.width) × \(display.height)).")

            try FileManager.default.createDirectory(
                at: recordingsDirectory, withIntermediateDirectories: true
            )
            let name = "Cineo-" + ISO8601DateFormatter().string(from: Date())
                .replacingOccurrences(of: ":", with: "-") + "-" + UUID().uuidString.prefix(8) + ".mp4"
            let url = recordingsDirectory.appendingPathComponent(String(name))
            targetURL = url
            currentFilename = url.lastPathComponent
            log("Output reserved in Movies/Cineo. H.264, 30 fps, no audio.")

            let config = SCStreamConfiguration()
            config.width = display.width
            config.height = display.height
            config.minimumFrameInterval = CMTime(value: 1, timescale: 30)
            config.queueDepth = 5
            config.pixelFormat = kCVPixelFormatType_32BGRA
            config.showsCursor = true
            config.capturesAudio = false

            let recordConfig = SCRecordingOutputConfiguration()
            recordConfig.outputURL = url
            recordConfig.outputFileType = .mp4
            recordConfig.videoCodecType = .h264

            let activeStream = SCStream(
                filter: SCContentFilter(display: display, excludingWindows: []),
                configuration: config, delegate: self
            )
            let activeOutput = SCRecordingOutput(configuration: recordConfig, delegate: self)
            try activeStream.addRecordingOutput(activeOutput)
            // Retain objects before starting, including during asynchronous
            // delegate callbacks or an early stream failure.
            stream = activeStream
            output = activeOutput
            log("Recording output attached. Starting capture…")
            try await activeStream.startCapture()
            if phase == .preparing {
                phase = .recording
                status = "Recording. Press Stop when you're finished."
                log("Capture started. Recording metrics are live.")
            }
        } catch {
            stream = nil
            output = nil
            fail("Unable to start capture: \(error.localizedDescription)")
        }
    }

    func stop() async {
        guard phase == .recording, let activeStream = stream,
              let activeOutput = output else { return }
        let durationAtStop = CMTimeGetSeconds(activeOutput.recordedDuration)
        let bytesAtStop = activeOutput.recordedFileSize
        log("Recording state before Stop: duration=\(durationAtStop.isFinite ? String(format: "%.2f", durationAtStop) : "invalid")s, bytes=\(bytesAtStop).")
        phase = .finalizing
        finalizationStarted = Date()
        finalizationElapsedSeconds = 0
        status = "Stopping capture and finalizing the MP4…"
        log("Stop requested. Stopping the stream and keeping the recording output attached.")
        monitor()

        do {
            // Per ScreenCaptureKit's SCStream contract, stopCapture also stops
            // an attached SCRecordingOutput and finalizes the movie. Do not
            // removeRecordingOutput immediately beforehand: competing stop
            // paths can invalidate the recording connection during teardown.
            // Retain both objects until the output's delegate completes.
            try await activeStream.stopCapture()
            if phase == .finalizing {
                log("Capture stream stopped. Awaiting the MP4 finalization callback.")
                status = "Capture stopped; waiting for MP4 verification…"
            }
        } catch {
            fail("Unable to stop capture safely: \(error.localizedDescription)")
        }
    }

    private func finish(_ id: ObjectIdentifier) async {
        guard let activeOutput = output, ObjectIdentifier(activeOutput) == id,
              let url = targetURL, phase != .failed else { return }
        phase = .verifying
        status = "ScreenCaptureKit finished. Checking the saved MP4…"
        log("Finalization callback received. Verifying video and file integrity.")
        monitor()
        do {
            let attrs = try FileManager.default.attributesOfItem(atPath: url.path)
            let bytes = (attrs[.size] as? NSNumber)?.int64Value ?? 0
            guard bytes > 0 else {
                fail("MP4 file exists but is empty. Recording was not verified.")
                return
            }
            let asset = AVURLAsset(url: url)
            let duration = CMTimeGetSeconds(try await asset.load(.duration))
            let video = try await asset.loadTracks(withMediaType: .video)
            guard duration.isFinite, duration > 0, !video.isEmpty else {
                fail("MP4 was written but no playable video track was found.")
                return
            }
            recordedSeconds = duration
            recordedBytes = bytes
            lastCompletedVideo = url
            stream = nil
            output = nil
            targetURL = nil
            finalizationStarted = nil
            phase = .complete
            status = "MP4 verified and ready. Choose Open MP4 or Show recordings."
            log("Verified MP4: video track present, \(Int(duration)) seconds, \(ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)).")
            monitorTask?.cancel()
            monitorTask = nil
        } catch {
            fail("MP4 validation failed: \(error.localizedDescription)")
        }
    }

    func openRecordingsFolder() {
        do {
            try FileManager.default.createDirectory(
                at: recordingsDirectory, withIntermediateDirectories: true
            )
            NSWorkspace.shared.open(recordingsDirectory)
        } catch {
            log("Could not open recordings folder: \(error.localizedDescription)", level: .error)
        }
    }

    func openLastRecording() {
        guard let video = lastCompletedVideo, phase == .complete else { return }
        NSWorkspace.shared.open(video)
    }

    func copyDiagnostics() {
        let text = logs.map { line in
            "[\(line.date.formatted(date: .omitted, time: .standard))] \(line.message)"
        }.joined(separator: "\n")
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        log("Activity log copied by user request.")
    }

    nonisolated func recordingOutputDidStartRecording(_ recordingOutput: SCRecordingOutput) {
        let id = ObjectIdentifier(recordingOutput)
        Task { @MainActor [weak self] in
            guard let self, let output = self.output,
                  ObjectIdentifier(output) == id else { return }
            self.log("ScreenCaptureKit confirmed recording started.")
        }
    }

    nonisolated func recordingOutputDidFinishRecording(_ recordingOutput: SCRecordingOutput) {
        let id = ObjectIdentifier(recordingOutput)
        Task { @MainActor [weak self] in
            await self?.finish(id)
        }
    }

    nonisolated func recordingOutput(_ recordingOutput: SCRecordingOutput, didFailWithError error: any Error) {
        let id = ObjectIdentifier(recordingOutput)
        let nsError = error as NSError
        let message = "\(nsError.domain) (\(nsError.code)): \(nsError.localizedDescription)"
        Task { @MainActor [weak self] in
            guard let self, let output = self.output,
                  ObjectIdentifier(output) == id else { return }
            self.stream = nil
            self.output = nil
            self.fail("Recording output failed: \(message)")
        }
    }

    nonisolated func stream(_ stream: SCStream, didStopWithError error: any Error) {
        let id = ObjectIdentifier(stream)
        let nsError = error as NSError
        let message = "\(nsError.domain) (\(nsError.code)): \(nsError.localizedDescription)"
        Task { @MainActor [weak self] in
            guard let self, let activeStream = self.stream,
                  ObjectIdentifier(activeStream) == id else { return }
            if self.phase == .finalizing || self.phase == .verifying {
                // An intentional stop may deliver a late stream error while
                // SCRecordingOutput is still finalizing. The recording delegate
                // and verified MP4 determine whether the recording succeeded.
                self.log("Stream interruption during finalization: \(message). Waiting for recording result.", level: .warning)
            } else if self.phase == .preparing || self.phase == .recording {
                self.stream = nil
                self.output = nil
                self.fail("Screen capture stopped unexpectedly: \(message)")
            }
        }
    }
}
