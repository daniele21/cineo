#!/usr/bin/env bash
set -euo pipefail
# Small proof: compile SwiftUI/ScreenCaptureKit/AVFoundation from CLT only.
# NOT the actual Cineo recorder. Never invokes xcodebuild.
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
package="$repo_root/Examples/CineoCLTProof"
output="${CINEO_CLT_PROOF_OUTPUT:-${TMPDIR:-/tmp}/cineo-clt-proof}"
app="$output/CineoCLTProof.app"

[[ "$(uname -s)" == Darwin ]] || { echo "macOS required" >&2; exit 2; }
for tool in swift xcode-select xcrun plutil codesign; do
  command -v "$tool" >/dev/null || { echo "Missing $tool" >&2; exit 2; }
done
echo "Developer tools: $(xcode-select -p)"
echo "macOS SDK: $(xcrun --sdk macosx --show-sdk-path)"
echo "Swift: $(swift --version | head -n 1)"
swift build --package-path "$package" --configuration debug
bin="$(swift build --package-path "$package" --configuration debug --show-bin-path)/CineoCLTProof"
[[ -x "$bin" ]] || { echo "Missing compiled executable" >&2; exit 3; }
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp "$bin" "$app/Contents/MacOS/CineoCLTProof"
cat > "$app/Contents/Info.plist" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
 "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>com.daniele21.cineo.cltproof</string>
<key>CFBundleExecutable</key><string>CineoCLTProof</string>
<key>CFBundleName</key><string>CineoCLTProof</string>
<key>CFBundleDisplayName</key><string>Cineo CLT Proof</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleVersion</key><string>1</string>
<key>CFBundleShortVersionString</key><string>0.0.1</string>
<key>LSMinimumSystemVersion</key><string>15.0</string>
<key>NSHighResolutionCapable</key><true/>
</dict></plist>
EOF
plutil -lint "$app/Contents/Info.plist"
codesign --force --sign - --timestamp=none "$app"
codesign --verify --strict --verbose=2 "$app"
echo "PASS: SwiftUI, ScreenCaptureKit and AVFoundation compilation; ad-hoc-signed .app."
echo "Proof path: $app"
echo "Not tested: real capture/TCC, zoom editor, video export or release signing."
