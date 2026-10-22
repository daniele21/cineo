#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
[[ "$(uname -s)" == "Darwin" ]] || { echo "SKIP: watchdog smoke requires macOS"; exit 0; }
TMP="$(mktemp -d "${TMPDIR:-/tmp}/cineo-watchdog.XXXXXXXX")"
trap 'rm -rf "$TMP"' EXIT
swiftc "$ROOT/Tools/CineoACEWatchdog/main.swift" -o "$TMP/CineoACEWatchdog"
python3 - "$TMP/CineoACEWatchdog" <<'PY'
import os, signal, subprocess, sys, tempfile, time
watchdog = sys.argv[1]

def child_pid(parent):
    for _ in range(100):
        result = subprocess.run(["pgrep", "-P", str(parent)], capture_output=True, text=True)
        if result.returncode == 0:
            return int(result.stdout.strip().splitlines()[0])
        time.sleep(.05)
    raise AssertionError("watchdog did not launch its test child")

def wait_gone(pid, seconds=12):
    deadline = time.monotonic() + seconds
    while time.monotonic() < deadline:
        if subprocess.run(["ps", "-p", str(pid)], stdout=subprocess.DEVNULL).returncode != 0:
            return
        time.sleep(.1)
    raise AssertionError(f"test child {pid} survived watchdog termination")

# Normal application quit: closing the pipe is the shutdown handshake.
supervisor = subprocess.Popen([watchdog, "/bin/sleep", "90"],
    stdin=subprocess.PIPE, stdout=subprocess.DEVNULL, stderr=subprocess.PIPE)
child = child_pid(supervisor.pid)
supervisor.stdin.close()
supervisor.wait(timeout=12)
wait_gone(child)
print("PASS: graceful quit reaps owned ACE substitute")

# Abnormal application crash: SIGKILL owner, not watchdog. Kernel EOF must
# still make the watcher terminate the server without a UI callback.
owner_code = """
import subprocess, sys, time
p = subprocess.Popen([sys.argv[1], '/bin/sleep', '90'],
    stdin=subprocess.PIPE, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
with open(sys.argv[2], 'w') as f:
    f.write(str(p.pid))
while True:
    time.sleep(1)
"""
with tempfile.TemporaryDirectory() as d:
    report = os.path.join(d, "pid")
    owner = subprocess.Popen([sys.executable, "-c", owner_code, watchdog, report])
    try:
        for _ in range(100):
            if os.path.isfile(report):
                break
            time.sleep(.05)
        assert os.path.isfile(report), "owner did not publish watchdog PID"
        watcher_pid = int(open(report).read())
        child = child_pid(watcher_pid)
        os.kill(owner.pid, signal.SIGKILL)
        owner.wait(timeout=5)
        wait_gone(child)
        print("PASS: SIGKILL of Cineo owner reaps owned ACE substitute")
    finally:
        if owner.poll() is None:
            owner.kill()
            owner.wait()
PY
