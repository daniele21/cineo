# Supervised ACE-Step lifecycle (Cineo Dev)

## User contract

- ACE-Step starts automatically when a durable music job needs it, and runs
  while Cineo is still open even if the Music Director view is dismissed.
- When the queue is empty, a Cineo-owned server stops after 10 minutes idle.
- A server already started by the user is **external**: Cineo may use it, but
  never kills it. Automatic shutdown only affects app-owned servers.
- Cmd-Q without work waits for the private supervisor to finish shutdown.
  With pending work, the user can remain in the app, finish all jobs and quit,
  or interrupt and quit. Queued jobs remain on disk.
- A job submitted before shutdown becomes interrupted, with an explicit retry.
  An unverified remote job ID is never polled blindly after reopening.
- Downloading model files is distinct from generation; cancellation is
  requested on app quit. Final download crash testing remains separate.

## Architecture

Cineo does not launch ace-server directly. The signed
`Contents/MacOS/CineoACEWatchdog` helper spawns and owns it, forwarding logs
to Cineo. A private stdin pipe is kept open only by Cineo. On graceful quit,
Cineo closes this pipe; on SIGKILL/crash the kernel closes it. The supervisor
then sends SIGTERM to its child, waits up to 5 seconds, escalates to SIGKILL
if needed and reaps it. No PID registry can accidentally target a foreign
process. This works under Apple Command Line Tools without Xcode.app.

The helper has no LaunchAgent, permissions, remote network connection or
long-lived service of its own. It inherits Cineo's app signing.

`CineoMusicJobQueue` persists to
`~/Library/Application Support/Cineo/music-job-queue.json`.
`CineoMusicRuntimeCoordinator` calls `ensureReady()` before a new job and
handles the 10-minute idle policy. `CineoApplicationDelegate` handles Cmd-Q
so window closure cannot accidentally shut down the engine.

## Manual verification

```bash
bash scripts/test-cineo-engine-lifecycle.sh
bash scripts/test-cineo.sh --interactive
pgrep -fl 'CineoACEWatchdog|ace-server'
```

The smoke starts `/bin/sleep` in place of ACE-Step and checks both graceful
pipe close and abrupt owner SIGKILL. It never downloads models or generates
music. Final physical-Mac E2E should additionally test a real job, quit while
generating, force-quit, startup failures and external server ownership.

## Limitations

The current engine endpoint remains fixed to 127.0.0.1:8080. A future
iteration can allocate a private free port and verify the server identity
through an authenticated/instance-aware handshake; the runtime currently
does not assume an external server's remote job ID survives restart.
