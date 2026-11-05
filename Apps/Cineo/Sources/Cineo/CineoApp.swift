import SwiftUI
import ScreenCaptureKit
import AVFoundation
import CoreMedia
import CoreVideo
import AppKit
import OSLog
import UniformTypeIdentifiers
import Combine
import CineoEvents

@main
struct CineoApp: App {
    @NSApplicationDelegateAdaptor(CineoApplicationDelegate.self) private var applicationDelegate
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
                    CaptureDashboard(recorder: recorder, editor: editor) { url in
                        Task { await editor.open(url) }
                    }
                }
            }
            .tint(CineoBrand.ocean)
            .onAppear { applicationDelegate.attach(editor: editor) }
        }
        .windowResizability(.contentSize)
    }
}


/// App termination is the only place allowed to tear down app-owned music
/// processes. Closing a sheet or editor window must not interrupt the queue.
@MainActor
final class CineoApplicationDelegate: NSObject, NSApplicationDelegate {
    private weak var editor: CineoEditorModel?
    private var subscription: AnyCancellable?
    private var finishAfterJobs = false
    private var isTerminating = false

    func attach(editor: CineoEditorModel) {
        guard self.editor !== editor else { return }
        self.editor = editor
        subscription = editor.musicQueue.$jobs.sink { [weak self] _ in
            Task { @MainActor [weak self] in self?.checkDeferredExit() }
        }
    }

    private func checkDeferredExit() {
        guard finishAfterJobs, let editor, !editor.musicQueue.hasWork else { return }
        finishAfterJobs = false
        NSApp.terminate(nil)
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard let editor else { return .terminateNow }
        if isTerminating { return .terminateLater }
        if editor.musicQueue.hasWork {
            let alert = NSAlert()
            alert.messageText = "Generazioni musicali in corso"
            alert.informativeText = "Chiudere Cineo interrompe il motore locale. La coda è salvata, ma i lavori in corso potrebbero dover essere ripetuti."
            alert.addButton(withTitle: "Resta in Cineo")
            alert.addButton(withTitle: "Esci al termine")
            alert.addButton(withTitle: "Interrompi ed esci")
            switch alert.runModal() {
            case .alertFirstButtonReturn:
                return .terminateCancel
            case .alertSecondButtonReturn:
                finishAfterJobs = true
                return .terminateCancel
            default:
                break
            }
        }
        isTerminating = true
        editor.musicQueue.prepareForAppExit()
        editor.aceBackend.downloader.cancel()
        Task {
            await editor.aceBackend.shutdown()
            sender.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
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

@MainActor
private final class CineoCaptureDashboardLayoutState: ObservableObject {
    @Published var recordingOptionsExpanded = true
}

private struct CaptureDashboard: View {
    @ObservedObject var recorder: CineoScreenRecorder
    @ObservedObject var editor: CineoEditorModel
    let onEditVideo: (URL) -> Void

    @StateObject private var layout = CineoCaptureDashboardLayoutState()

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
        GeometryReader { geometry in
            let compact = geometry.size.width < 850
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    header
                    if compact {
                        VStack(alignment: .leading, spacing: 16) {
                            captureActions
                            captureOptions
                        }
                    } else {
                        HStack(alignment: .top, spacing: 16) {
                            captureActions.frame(maxWidth: .infinity, alignment: .leading)
                            captureOptions.frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    recordingStatus
                    activityLog
                    Text("Tutto rimane sul tuo Mac · Dev \(buildRevision) · PID \(ProcessInfo.processInfo.processIdentifier)")
                        .font(.caption2.monospaced())
                        .foregroundStyle(.tertiary)
                        .textSelection(.enabled)
                }
                .frame(maxWidth: 1080, alignment: .leading)
                .padding(22)
                .frame(maxWidth: .infinity, alignment: .top)
            }
        }
        .frame(minWidth: 620, minHeight: 490)
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 12) {
            CineoBrandSymbol(size: 40)
            VStack(alignment: .leading, spacing: 3) {
                Text("Cineo")
                    .font(CineoBrand.displayFont(size: 25))
                Text("Registra lo schermo. Cura il montaggio.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 10)
            CineoMusicQueueButton(editor: editor)
        }
    }

    private var captureActions: some View {
        VStack(alignment: .leading, spacing: 13) {
            Label("Crea un video", systemImage: "record.circle")
                .font(.headline)
            Text("Registra il display principale oppure apri un MP4 per modificarlo.")
                .font(.caption)
                .foregroundStyle(.secondary)

            if recorder.phase == .recording {
                Button {
                    Task { await recorder.stop() }
                } label: {
                    Label("Termina registrazione", systemImage: "stop.fill")
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
                .controlSize(.large)
            } else {
                Button {
                    Task { await recorder.start() }
                } label: {
                    Label("Registra lo schermo", systemImage: "record.circle")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(recorder.phase.isWorking)
            }
            Button {
                let panel = NSOpenPanel()
                // Project packages are directories; existing editor code
                // validates the chosen file/project before opening it.
                panel.canChooseDirectories = true
                panel.allowsMultipleSelection = false
                panel.allowedContentTypes = []
                if panel.runModal() == .OK, let url = panel.url {
                    onEditVideo(url)
                }
            } label: {
                Label("Apri MP4 o progetto…", systemImage: "film")
            }
            if let url = recorder.lastCompletedVideo, recorder.phase == .complete {
                HStack(spacing: 10) {
                    Button {
                        onEditVideo(url)
                    } label: {
                        Label("Modifica ultima registrazione", systemImage: "slider.horizontal.3")
                    }
                    .help(url.lastPathComponent)
                    Button {
                        recorder.openLastRecording()
                    } label: {
                        Image(systemName: "play.rectangle")
                    }
                    .help("Apri l'ultimo MP4")
                }
            }
            Button {
                recorder.openRecordingsFolder()
            } label: {
                Label("Cartella registrazioni", systemImage: "folder")
            }
            .font(.caption)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(.quaternary.opacity(0.18), in: RoundedRectangle(cornerRadius: 12))
    }

    private var captureOptions: some View {
        VStack(alignment: .leading, spacing: 10) {
            DisclosureGroup("Opzioni di registrazione", isExpanded: $layout.recordingOptionsExpanded) {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 175), alignment: .leading)],
                          alignment: .leading, spacing: 10) {
                    Toggle("Audio sistema", isOn: $recorder.captureSystemAudio)
                    Toggle("Microfono", isOn: $recorder.captureMicrophone)
                    Toggle("Registra click", isOn: $recorder.captureClickEvents)
                        .help("Registra i click per Smart Camera e Auto Edit")
                    Toggle("Movimento cursore", isOn: $recorder.capturePointerMovement)
                    Toggle("Cursore ricostruito (beta)", isOn: $recorder.captureIndependentCursor)
                        .help("Nasconde il puntatore nel video originale e lo ricrea in postproduzione")
                }
                .toggleStyle(.checkbox)
                .disabled(recorder.phase == .recording || recorder.phase.isWorking)
                .padding(.top, 10)
                Text("Le opzioni sono disattivate per default. La ricostruzione del cursore è sperimentale e richiede telemetria locale.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .font(.headline)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(.quaternary.opacity(0.18), in: RoundedRectangle(cornerRadius: 12))
    }

    private var recordingStatus: some View {
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
                    .font(.headline.monospacedDigit())
            }
            Text(recorder.status)
                .font(.callout)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 16) {
                Label("Durata \(timeText)", systemImage: "clock")
                Label(fileSizeText, systemImage: "doc")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            if recorder.phase == .finalizing || recorder.phase == .verifying {
                Text("Finalizzazione: \(recorder.finalizationElapsedSeconds) s · in attesa della verifica del sistema, senza percentuale stimabile.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if recorder.finalizationElapsedSeconds >= 15 {
                    Text("L'operazione sta richiedendo più tempo del previsto. Il video originale non è stato eliminato; controlla i log per eventuali errori.")
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
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.18), in: RoundedRectangle(cornerRadius: 12))
    }

    private var activityLog: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("Registro attività · \(recorder.logs.count)", systemImage: "list.bullet.rectangle")
                    .font(.headline)
                Spacer()
                Button("Copia diagnostica") { recorder.copyDiagnostics() }
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
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            .font(.caption)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .id(entry.id)
                        }
                    }
                }
                .frame(height: 158)
                .onChange(of: recorder.logs.count) { _, _ in
                    if let last = recorder.logs.last {
                        proxy.scrollTo(last.id, anchor: .bottom)
                    }
                }
            }
        }
        .padding(16)
        .background(.quaternary.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
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
    @Published var captureClickEvents = false
    @Published var capturePointerMovement = false
    @Published var captureIndependentCursor = false
    @Published var captureSystemAudio = false
    @Published var captureMicrophone = false

    private var firstFrameObserver: CineoFirstFrameObserver?
    private var pointerMonitor: Any?
    private var pointerSamplingTask: Task<Void, Never>?
    private var capturedClicks: [CineoPointerRawClick] = []
    private var selectedDisplayFrame: CGRect?

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
        stopPointerMonitor()
        phase = .failed
        status = message
        log(message, level: .error)
        monitorTask?.cancel()
        monitorTask = nil
    }

    private func stopPointerMonitor() {
        pointerSamplingTask?.cancel()
        pointerSamplingTask = nil
        if let pointerMonitor { NSEvent.removeMonitor(pointerMonitor) }
        pointerMonitor = nil
    }

    private func beginPointerMonitor(on frame: CGRect) {
        stopPointerMonitor()
        capturedClicks = []
        selectedDisplayFrame = frame
        guard captureClickEvents || capturePointerMovement else { return }
        if capturePointerMovement || captureIndependentCursor {
            // Sample only mouse location. This does not observe keyboard input or AX content.
            // The same monotonic clock anchors both pointer samples and clicks to first video PTS.
            pointerSamplingTask = Task { @MainActor [weak self] in
                while !Task.isCancelled {
                    guard let self, self.phase == .recording,
                          let currentFrame = self.selectedDisplayFrame else { return }
                    if self.capturedClicks.count < 180_000 {
                        let point = NSEvent.mouseLocation
                        let x = (point.x - currentFrame.minX) / currentFrame.width
                        let y = (currentFrame.maxY - point.y) / currentFrame.height
                        if x.isFinite, y.isFinite, (0...1).contains(x), (0...1).contains(y) {
                            self.capturedClicks.append(.init(
                                hostSeconds: ProcessInfo.processInfo.systemUptime,
                                x: x, y: y, kind: .moved))
                        }
                    }
                    try? await Task.sleep(for: .milliseconds(50))
                }
            }
        }
        if captureClickEvents {
            pointerMonitor = NSEvent.addGlobalMonitorForEvents(
                matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
            let timestamp = event.timestamp
            let isRight = event.type == .rightMouseDown
            let pt = NSEvent.mouseLocation
            Task { @MainActor [weak self] in
                guard let self, self.phase == .recording,
                      self.capturedClicks.count < 180_000,
                      let frame = self.selectedDisplayFrame else { return }
                let x = (pt.x - frame.minX) / frame.width
                let y = (frame.maxY - pt.y) / frame.height
                guard x.isFinite, y.isFinite, (0...1).contains(x),
                      (0...1).contains(y) else { return }
                let kind: CineoPointerEvent.Kind = isRight ? .rightClick : .leftClick
                self.capturedClicks.append(CineoPointerRawClick(
                    hostSeconds: timestamp, x: x, y: y, kind: kind))
            }
        }
            if pointerMonitor == nil {
                log("Monitoraggio click non disponibile. Eventuale percorso cursore campionato separatamente.",
                    level: .warning)
            }
        }
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
        firstFrameObserver = nil
        capturedClicks = []
        stopPointerMonitor()
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
            if captureMicrophone {
                let permission = await AVCaptureDevice.requestAccess(for: .audio)
                guard permission else {
                    fail("Microfono non autorizzato. Abilitalo in Impostazioni di Sistema o disattiva l'opzione.")
                    return
                }
            }

            try FileManager.default.createDirectory(
                at: recordingsDirectory, withIntermediateDirectories: true
            )
            let name = "Cineo-" + ISO8601DateFormatter().string(from: Date())
                .replacingOccurrences(of: ":", with: "-") + "-" + UUID().uuidString.prefix(8) + ".mp4"
            let url = recordingsDirectory.appendingPathComponent(String(name))
            targetURL = url
            currentFilename = url.lastPathComponent
            log("Output reserved in Movies/Cineo. H.264, 30 fps; system audio=\(captureSystemAudio), mic=\(captureMicrophone), clicks=\(captureClickEvents), movement=\(capturePointerMovement), independentCursor=\(captureIndependentCursor).")

            let config = SCStreamConfiguration()
            config.width = display.width
            config.height = display.height
            config.minimumFrameInterval = CMTime(value: 1, timescale: 30)
            config.queueDepth = 5
            config.pixelFormat = kCVPixelFormatType_32BGRA
            config.showsCursor = !captureIndependentCursor
            config.capturesAudio = captureSystemAudio
            config.captureMicrophone = captureMicrophone
            config.excludesCurrentProcessAudio = true

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
            if captureClickEvents || capturePointerMovement || captureIndependentCursor {
                let anchor = CineoFirstFrameObserver()
                do {
                    try activeStream.addStreamOutput(
                        anchor, type: .screen,
                        sampleHandlerQueue: DispatchQueue(label: "com.cineo.pointer.frame-anchor"))
                    firstFrameObserver = anchor
                } catch {
                    log("Telemetria click non disponibile: \(error.localizedDescription). Registrazione video invariata.",
                        level: .warning)
                }
            }
            // Independent cursor requires source-clock anchor and a usable
            // captured display frame BEFORE hiding the cursor in the MP4.
            if captureIndependentCursor {
                guard firstFrameObserver != nil,
                      NSScreen.screens.contains(where: {
                          ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?
                              .uint32Value == display.displayID
                      }) else {
                    throw CineoEventsError.invalidClock
                }
            }
            // Retain objects before starting, including during asynchronous
            // delegate callbacks or an early stream failure.
            stream = activeStream
            output = activeOutput
            log("Recording output attached. Starting capture…")
            try await activeStream.startCapture()
            if phase == .preparing {
                phase = .recording
                status = "Registrazione attiva. Premi Stop per terminare."
                if (captureClickEvents || capturePointerMovement || captureIndependentCursor) && firstFrameObserver != nil {
                    // Global NSEvent uses host uptime and never captures typed text.
                    let screen = NSScreen.screens.first {
                        ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?
                            .uint32Value == display.displayID
                    } ?? NSScreen.main
                    if let screen {
                        beginPointerMonitor(on: screen.frame)
                    } else {
                        log("Coordinate monitor non disponibili: telemetria disattivata.", level: .warning)
                    }
                }
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
        stopPointerMonitor()
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
            // The raw recording is retained even when the independent cursor
            // metadata cannot be finalized. Surface that failure prominently.
            var independentCursorReady = !captureIndependentCursor
            if captureClickEvents || capturePointerMovement || captureIndependentCursor {
                do {
                    if let stamp = firstFrameObserver?.firstFrameHostSeconds {
                        let clock = try CineoCaptureClock(
                            firstFrameHostSeconds: stamp, firstFramePTSSeconds: stamp)
                        let events = capturedClicks.compactMap { click -> CineoPointerEvent? in
                            guard let t = clock.relativeSeconds(
                                hostSeconds: click.hostSeconds, recordedDuration: duration) else { return nil }
                            return CineoPointerEvent(sourceSeconds: t, x: click.x, y: click.y, kind: click.kind)
                        }.sorted { $0.sourceSeconds < $1.sourceSeconds }
                        if events.isEmpty && !capturedClicks.isEmpty {
                            log("Timestamp click non allineati al video: nessun sidecar scritto.", level: .warning)
                        } else {
                            let sidecar = try CineoPointerSidecar(
                                events: events,
                                cursorMode: captureIndependentCursor ? .independentOverlay : .embedded)
                            try CineoPointerRecordingStore().save(sidecar, for: url)
                            independentCursorReady = true
                            log("Telemetria puntatore salvata: \(events.count) eventi (click/movimento) in JSON locale.")
                        }
                    } else {
                        log("Primo frame non disponibile: nessuna telemetria salvata (video integro).", level: .warning)
                    }
                } catch {
                    log("Telemetria click non salvata: \(error.localizedDescription). MP4 preservato.", level: .warning)
                }
            }
            if captureSystemAudio || captureMicrophone {
                if let audio = try? await asset.loadTracks(withMediaType: .audio), audio.isEmpty {
                    log("Video verificato, ma il file non contiene una traccia audio. Verifica permessi e impostazioni.", level: .warning)
                }
            }
            recordedSeconds = duration
            recordedBytes = bytes
            lastCompletedVideo = url
            stream = nil
            output = nil
            targetURL = nil
            firstFrameObserver = nil
            capturedClicks = []
            finalizationStarted = nil
            phase = .complete
            status = independentCursorReady
                ? "MP4 verificato e pronto. Apri il video o l'editor."
                : "MP4 salvato, ma cursore ricostruito NON disponibile: metadati mancanti. Ripeti la cattura in modalità cursore standard."
            if !independentCursorReady {
                log("ATTENZIONE: MP4 senza cursore incorporato, sidecar v2 non valido o assente. Non esportare come video finale.", level: .error)
            }
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
