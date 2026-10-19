#!/usr/bin/env bash
set -euo pipefail

# P0 source/build experiment; not a screen recording or product-quality benchmark.
# Default --list does not clone, install or change the host. --run requires macOS.
ROOT="${CINEO_BENCH_ROOT:-/tmp/cineo-upstream-bench}"
MODE="${1:---list}"
TARGET="${2:-all}"

usage() {
  echo "Usage: bash scripts/benchmark-upstreams.sh --list | --run orbit|cinescreen|bettercapture|all"
  exit 2
}

if [[ "$MODE" != "--list" && "$MODE" != "--run" ]]; then usage; fi
if [[ "$TARGET" != "orbit" && "$TARGET" != "cinescreen" && "$TARGET" != "bettercapture" && "$TARGET" != "all" ]]; then
  if [[ "$MODE" == "--run" ]]; then usage; fi
fi

ORBIT_SHA=219c4c8ad9965229aa84271c5201b1b8ad26eb7a
CINESCREEN_SHA=ff4764b9ca50c6424f6746a05d7aff2abb70444b
BETTER_SHA=ab852b44c4dd09c8e2ae69e7858a1b67e1cd17af

echo "Cineo P0 upstream source/build targets (no app E2E validation)"
echo "orbit         diip3sh/orbit                 $ORBIT_SHA  Xcode26"
echo "cinescreen    jasonzh0/CineScreen          $CINESCREEN_SHA  XcodeGen + Metal"
echo "bettercapture jsattler/BetterCapture      $BETTER_SHA  Xcode"
echo "Work dir: $ROOT"
if [[ "$MODE" == "--list" ]]; then exit 0; fi

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "Error: native Xcode builds require macOS." >&2; exit 3
fi
command -v xcodebuild >/dev/null || { echo "Install Xcode." >&2; exit 3; }
command -v git >/dev/null || { echo "Install Git." >&2; exit 3; }

run_one() {
  local name="$1" url="$2" sha="$3" scheme="$4"
  local dir="$ROOT/$name"
  mkdir -p "$ROOT"
  if [[ ! -d "$dir/.git" ]]; then
    git clone --filter=blob:none "$url" "$dir"
  fi
  git -C "$dir" fetch --depth 1 origin "$sha"
  git -C "$dir" checkout --detach "$sha"
  echo "Source pinned: $(git -C "$dir" rev-parse HEAD)"
  echo "Toolchain: $(xcodebuild -version | tr '\\n' ' ')"
  if [[ "$name" == cinescreen ]]; then
    command -v xcodegen >/dev/null || { echo "XcodeGen required; not installing automatically." >&2; return 4; }
    (cd "$dir" && make project)
  fi
  local proj="$dir/$scheme.xcodeproj"
  if [[ "$name" == "orbit" ]]; then proj="$dir/Reco.xcodeproj"; fi
  if [[ "$name" == "cinescreen" ]]; then proj="$dir/CineScreen.xcodeproj"; fi
  mkdir -p "$ROOT/logs"
  echo "Detected Xcode schemes:"
  xcodebuild -list -project "$proj" | tail -n 30
  echo "Compiling $name without signing; this does not prove capture/permissions."
  (
    set -o pipefail
    xcodebuild -project "$proj" -scheme "$scheme" -configuration Debug \
      -destination 'platform=macOS' -derivedDataPath "$ROOT/DerivedData/$name" \
      CODE_SIGNING_ALLOWED=NO build 2>&1 | tee "$ROOT/logs/$name-build.log"
  )
}

if [[ "$TARGET" == orbit || "$TARGET" == all ]]; then
  run_one orbit https://github.com/diip3sh/orbit.git "$ORBIT_SHA" Reco
fi
if [[ "$TARGET" == cinescreen || "$TARGET" == all ]]; then
  run_one cinescreen https://github.com/jasonzh0/CineScreen.git "$CINESCREEN_SHA" CineScreen
fi
if [[ "$TARGET" == bettercapture || "$TARGET" == all ]]; then
  run_one bettercapture https://github.com/jsattler/BetterCapture.git "$BETTER_SHA" BetterCapture
fi

echo "Build logs in $ROOT/logs. Native UI/capture/export still require signed real-Mac E2E."
