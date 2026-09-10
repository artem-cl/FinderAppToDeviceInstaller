#!/bin/bash
set -euo pipefail
PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="$PROJECT_DIR/build"
DIST_DIR="$PROJECT_DIR/dist"
WORKFLOW="$BUILD_DIR/Install on Device.workflow"
APP="$WORKFLOW/Contents/Resources/Install on Device.app"
mkdir -p "$BUILD_DIR" "$DIST_DIR"
python3 "$PROJECT_DIR/scripts/package.py" "$WORKFLOW"
mkdir -p "$APP/Contents/MacOS"
xcrun swiftc -O -module-cache-path "$BUILD_DIR/swift-cache" \
  "$PROJECT_DIR/Sources/DeviceInstaller.swift" -o "$APP/Contents/MacOS/DeviceInstaller"
/usr/bin/codesign --force --sign - "$APP"
/usr/bin/codesign --verify --deep --strict "$APP"
/usr/bin/plutil -lint "$WORKFLOW/Contents/Info.plist" "$WORKFLOW/Contents/document.wflow" "$APP/Contents/Info.plist"
/usr/bin/ditto -c -k --keepParent "$WORKFLOW" "$DIST_DIR/Install on Device.zip"
printf 'Built: %s\nRelease archive: %s\n' "$WORKFLOW" "$DIST_DIR/Install on Device.zip"
