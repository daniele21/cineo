import SwiftUI
import ScreenCaptureKit
import AVFoundation
import CoreMedia
import CoreVideo
import AppKit

/// First independent Cineo app: real macOS capture backed directly by
/// ScreenCaptureKit's recording output. No Xcode project or Orbit binaries.
@main
struct CineoApp: App {
    @StateObject private var recorder = CineoScreenRecorder()

    var body: some Scene {
        WindowGroup("Cineo") {
            ContentView(recorder: recorder)
        }
        .windowResizability(.contentSize)
    }
}

private struct ContentView: View {
    @ObservedObject var recorder: CineoScreenRecorder

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Image(systemName: "record.circle")
                    .font(.largeTitle)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Cineo").font(.title.bold())
                    Text("Local-first native capture • SwiftPM + Command Line Tools")
                        .foregroundStyle(.secondary)
                }
            }
            Divider()
            Text("Record the main display to a local H.264 MP4. No cloud upload.")
                .font(.headline)
            Text("The editor and automatic cinematic zooms are not yet connected to this CLT-native app.")
                .foregroundStyle(.secondary)
            HStack(spacing: 12) {
                if recorder.isRecording {
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
                }
                Button {
                    recorder.openRecordingsFolder()
                } label: {
                    Label("Show recordings", systemImage: "folder")
                }
                .disabled(recorder.isBusy)
            }
            .disabled(recorder.isBusy)
            HStack {
                Image(systemName: recorder.isRecording ? "record.circle.fill" : "info.circle")
                    .foregroundStyle(recorder.isRecording ? .red : .secondary)
                Text(recorder.status)
                    .textSelection(.enabled)
            }
            .font(.callout)
            Text("Screen Recording permission is requested by macOS only when capture starts. You control permission and may revoke it in System Settings.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(width: 575)
        .padding(24)
    }
}

/// MainActor confines UI and start/stop transitions. The delegate only
/// transfers plain error messages back to the main actor.
@MainActor
final class CineoScreenRecorder: NSObject, ObservableObject, SCRecordingOutputDelegate, SCStreamDelegate {
    @Published private(set) var isRecording = false
    @Published private(set) var isBusy = false
    @Published private(set) var status = "Ready. No screen permissions requested."
    private var stream: SCStream?
    private var output: SCRecordingOutput?

    private var recordingsDirectory: URL {
        FileManager.default.urls(for: .moviesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Cineo", isDirectory: true)
    }

    func start() async {
        guard stream == nil, !isBusy else { return }
        isBusy = true
        defer { isBusy = false }
        do {
            // This is the first API that may trigger Screen Recording permission.
            let available = try await SCShareableContent.excludingDesktopWindows(
                false, onScreenWindowsOnly: true
            )
            guard let display = available.displays.first(where: {
                $0.displayID == CGMainDisplayID()
            }) ?? available.displays.first else {
                status = "No display available. Check Screen Recording permission."
                return
            }
            let folder = recordingsDirectory
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let name = "Cineo-" + ISO8601DateFormatter().string(from: Date())
                .replacingOccurrences(of: ":", with: "-") + ".mp4"
            let url = folder.appendingPathComponent(name)
            let filter = SCContentFilter(display: display, excludingWindows: [])
            let config = SCStreamConfiguration()
            config.width = display.width
            config.height = display.height
            config.minimumFrameInterval = CMTime(value: 1, timescale: 30)
            config.queueDepth = 5
            config.pixelFormat = kCVPixelFormatType_32BGRA
            config.showsCursor = true
            config.capturesAudio = false  // No microphone or system-audio collection.
            let recording = SCRecordingOutputConfiguration()
            recording.outputURL = url
            recording.outputFileType = .mp4
            recording.videoCodecType = .h264
            let activeStream = SCStream(filter: filter, configuration: config, delegate: self)
            let activeOutput = SCRecordingOutput(configuration: recording, delegate: self)
            try activeStream.addRecordingOutput(activeOutput)
            try await activeStream.startCapture()
            stream = activeStream
            output = activeOutput
            isRecording = true
            status = "Recording to Movies/Cineo. Click Stop to finish."
        } catch {
            stream = nil
            output = nil
            isRecording = false
            status = "Capture failed: \(error.localizedDescription)"
        }
    }

    func stop() async {
        guard let activeStream = stream, !isBusy else { return }
        isBusy = true
        defer { isBusy = false }
        do {
            try await activeStream.stopCapture()
            // Retain delegate/output until ScreenCaptureKit confirms finalization.
            stream = nil
            isRecording = false
            status = "Stopped capture. Finalizing MP4…"
        } catch {
            status = "Stop failed: \(error.localizedDescription)"
        }
    }

    func openRecordingsFolder() {
        let folder = recordingsDirectory
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            NSWorkspace.shared.open(folder)
        } catch {
            status = "Cannot open recordings folder: \(error.localizedDescription)"
        }
    }

    nonisolated func recordingOutputDidStartRecording(_ recordingOutput: SCRecordingOutput) {
        Task { @MainActor [weak self] in
            self?.status = "Recording in progress. Video remains on this Mac."
        }
    }

    nonisolated func recordingOutputDidFinishRecording(_ recordingOutput: SCRecordingOutput) {
        Task { @MainActor [weak self] in
            self?.output = nil
            self?.status = "MP4 finalized in Movies/Cineo."
        }
    }

    nonisolated func recordingOutput(_ recordingOutput: SCRecordingOutput, didFailWithError error: any Error) {
        let message = error.localizedDescription
        Task { @MainActor [weak self] in
            self?.status = "Recording output error: \(message)"
            self?.isRecording = false
            self?.stream = nil
            self?.output = nil
        }
    }

    nonisolated func stream(_ stream: SCStream, didStopWithError error: any Error) {
        let message = error.localizedDescription
        Task { @MainActor [weak self] in
            self?.status = "Capture stopped unexpectedly: \(message)"
            self?.isRecording = false
            self?.stream = nil
            self?.output = nil
        }
    }
}
