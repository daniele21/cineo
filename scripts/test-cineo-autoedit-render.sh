#!/usr/bin/env bash
set -euo pipefail
# Isolated actual-media post-production check. Doesn't build, replace, sign,
# launch or request permission for the running Cineo Dev.app.
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
if [[ "${1:-}" == "--help" || "$#" -ne 2 ]]; then
  echo "Usage: bash scripts/test-cineo-autoedit-render.sh /absolute/input.mp4 /absolute/edited.mp4"
  echo "Both paths must be absolute. Output must not exist. Never alters input or Cineo Dev.app."
  [[ "${1:-}" == "--help" ]] && exit 0
  exit 2
fi
[[ "$(uname -s)" == Darwin ]] || { echo "Requires macOS" >&2; exit 2; }
INPUT="$1"
OUTPUT="$2"
[[ "$INPUT" == /* && "$OUTPUT" == /* ]] || { echo "Use absolute file paths." >&2; exit 2; }
[[ -f "$INPUT" && ! -L "$INPUT" ]] || { echo "Input must be an existing regular MP4 file, not a symlink." >&2; exit 2; }
[[ "$INPUT" == *.mp4 ]] || { echo "Input must have .mp4 extension." >&2; exit 2; }
[[ "$OUTPUT" == *.mp4 && ! -e "$OUTPUT" && ! -L "$OUTPUT" ]] || { echo "Output must be a new .mp4 path." >&2; exit 2; }
[[ "$OUTPUT" != "$INPUT" ]] || { echo "Cannot overwrite original." >&2; exit 2; }
[[ -d "$(dirname "$OUTPUT")" ]] || { echo "Create destination folder first." >&2; exit 2; }
export DEVELOPER_DIR=/Library/Developer/CommandLineTools
[[ -d "$DEVELOPER_DIR" ]] || { echo "Missing Apple Command Line Tools." >&2; exit 2; }
command -v shasum >/dev/null || exit 2
command -v swift >/dev/null || exit 2

cd "$ROOT"
BEFORE="$(shasum -a 256 "$INPUT" | awk '{print $1}')"
echo "Source SHA-256: $BEFORE"
echo "Rendering with CLT Core Image + AVFoundation (1920 x 1080, no audio)."
swift run --package-path Packages/CineoScene --configuration release cineo-scene-spike "$INPUT" "$OUTPUT"
AFTER="$(shasum -a 256 "$INPUT" | awk '{print $1}')"
[[ "$BEFORE" == "$AFTER" ]] || { echo "ERROR: original source changed!" >&2; exit 3; }
echo "Original MP4 untouched. Checking exported MP4 metadata…"
swift run --package-path Packages/CineoExportProbe --configuration release cineo-export-probe \
  --file "$OUTPUT" --width 1920 --height 1080 --min-seconds 2 --codec h264
echo "PASS: real source converted, output validated; original source SHA unchanged."
echo "Visual inspection is still required; open the file with QuickTime and review zoom/padding."
echo "$OUTPUT"
