import Foundation
import Darwin

// A tiny parent-death supervisor, deliberately separate from Cineo.
// stdin is a private pipe whose only writer is the owning Cineo process.
// When that writer disappears (normal quit, SIGKILL, crash), ACE is reaped.
// External ACE servers are NEVER children of this helper.
guard CommandLine.arguments.count >= 2 else {
    fputs("CineoACEWatchdog: missing executable\n", stderr)
    exit(64)
}
let executable = CommandLine.arguments[1]
guard FileManager.default.isExecutableFile(atPath: executable) else {
    fputs("CineoACEWatchdog: ACE executable is unavailable\n", stderr)
    exit(66)
}

let server = Process()
server.executableURL = URL(fileURLWithPath: executable)
server.arguments = Array(CommandLine.arguments.dropFirst(2))
server.currentDirectoryURL = URL(fileURLWithPath: executable).deletingLastPathComponent().deletingLastPathComponent()
server.standardInput = FileHandle.nullDevice // Never inherit the owner's liveness pipe.
server.standardOutput = FileHandle.standardOutput
server.standardError = FileHandle.standardError

do {
    try server.run()
} catch {
    fputs("CineoACEWatchdog: launch failed: \(error)\n", stderr)
    exit(70)
}

DispatchQueue.global(qos: .userInitiated).async {
    var byte: UInt8 = 0
    while true {
        let count = read(STDIN_FILENO, &byte, 1)
        if count == 0 { break }
        if count < 0 {
            if errno == EINTR { continue }
            break // Error means liveness is no longer provable: fail closed.
        }
    }
    guard server.isRunning else { return }
    server.terminate()
    for _ in 0..<50 {
        if !server.isRunning { return }
        usleep(100_000)
    }
    // Only target the Process object this supervisor launched.
    if server.isRunning { _ = kill(server.processIdentifier, SIGKILL) }
}
server.waitUntilExit()
exit(server.terminationStatus)
