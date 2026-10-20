#!/usr/bin/env bash
set -euo pipefail

echo "Cineo developer environment (native P1 + package experiments)"
echo "OS: $(uname -s) $(uname -m)"
if command -v swift >/dev/null 2>&1; then
  swift --version | head -n 2
else
  echo "Swift: missing (required for CineoDirector prototype)"
fi

if [[ "$(uname -s)" == "Darwin" ]]; then
  if command -v xcodebuild >/dev/null 2>&1; then
    xcodebuild -version
    echo "Xcode path: $(xcode-select -p)"
  else
    echo "Xcode CLI: missing; cannot build the native upstreams"
  fi
  if command -v xcodegen >/dev/null 2>&1; then
    xcodegen --version
  else
    echo "XcodeGen: not installed (required for CineScreen)"
  fi
  echo "Code signing identities (count):"
  if command -v security >/dev/null 2>&1; then
    security find-identity -v -p codesigning | grep -c 'Apple Development' || true
  fi
else
  echo "Native macOS capture, permissions and export cannot be validated on this host."
fi

if [[ -f Packages/CineoDirector/Package.swift ]]; then
  echo "CineoDirector Swift package: present"
else
  echo "CineoDirector Swift package: not present on this branch"
fi

if [[ -f Packages/CineoProject/Package.swift ]]; then
  echo "CineoProject Swift package: present"
fi
if [[ -f scripts/native-smoke-doctor.sh ]]; then
  echo "Native smoke doctor: present (requires a built macOS Cineo.app)"
fi
