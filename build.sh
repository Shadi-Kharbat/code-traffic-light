#!/bin/bash
# Builds "Claude Traffic Light.app" into ./build using swiftc (no Xcode project needed).
set -euo pipefail
cd "$(dirname "$0")"

APP="build/Claude Traffic Light.app"
ARCH="$(uname -m)"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

swiftc -O \
  -swift-version 5 \
  -target "${ARCH}-apple-macosx13.0" \
  -o "$APP/Contents/MacOS/ClaudeTrafficLight" \
  Sources/main.swift

cp Info.plist "$APP/Contents/Info.plist"
printf 'APPL????' > "$APP/Contents/PkgInfo"
codesign --force --sign - "$APP" >/dev/null 2>&1 || true

echo "Built: $PWD/$APP"
