#!/usr/bin/env bash
set -euo pipefail
# Pre-merge gate for independently maintained Auto Edit packages. This script
# runs only packages available in the current checkout. CI native rendering is
# a separate macOS-only gate and may never be treated as a green Linux test.
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

run_package() {
  local pkg="$1"
  if [[ -f "Packages/$pkg/Package.swift" ]]; then
    printf '\n== Testing %s ==\n' "$pkg"
    swift test --package-path "Packages/$pkg"
  else
    printf 'SKIP: %s not integrated in this branch\n' "$pkg"
  fi
}
run_package CineoProject
run_package CineoDirector
if [[ -f "Packages/CineoDirector/Sources/CineoCameraBenchmark/main.swift" ]]; then
  printf '\n== Checking synthetic camera quality fixtures ==\n'
  swift run --package-path Packages/CineoDirector cineo-camera-benchmark
fi
run_package CineoEditPlanner
run_package CineoEvents
run_package CineoScene

if [[ -f "Tools/CineoCLI/Package.swift" ]]; then
  printf '\n== Building headless CLI ==\n'
  swift build --package-path Tools/CineoCLI --configuration release
fi

echo "PASS: available pure Swift test and CLI packages."
echo "NOT VERIFIED: native H.264 rendering, source SHA, frame quality, real Mac capture and export."
