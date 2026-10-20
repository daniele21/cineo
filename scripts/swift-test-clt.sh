#!/usr/bin/env bash
set -euo pipefail
# Work around Apple CLT SwiftPM versions that do not locate Testing.framework
# or its runtime by default. Never installs Xcode or third-party tools.
# Usage: bash scripts/swift-test-clt.sh --package-path Packages/CineoDirector

if [[ "$(uname -s)" != Darwin ]]; then
  exec swift test "$@"
fi

if [[ -z "${DEVELOPER_DIR:-}" && -d /Library/Developer/CommandLineTools ]]; then
  export DEVELOPER_DIR=/Library/Developer/CommandLineTools
fi

dirs=()
[[ -n "${DEVELOPER_DIR:-}" ]] && dirs+=("$DEVELOPER_DIR")
dirs+=("/Library/Developer/CommandLineTools")

for developer in "${dirs[@]}"; do
  framework_dir="$developer/Library/Developer/Frameworks"
  swift_lib_dir="$developer/Library/Developer/usr/lib"
  if [[ -d "$framework_dir/Testing.framework" ]]; then
    echo "Using Apple CLT Swift Testing framework: $framework_dir" >&2
    exec swift test \
      -Xswiftc -F -Xswiftc "$framework_dir" \
      -Xlinker -F -Xlinker "$framework_dir" \
      -Xlinker -rpath -Xlinker "$framework_dir" \
      -Xlinker -rpath -Xlinker "$swift_lib_dir" \
      "$@"
  fi
done

echo "Testing.framework not found in CLT developer directories; trying standard swift test." >&2
exec swift test "$@"
