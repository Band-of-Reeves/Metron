#!/bin/bash
# Builds Metron.app into ./dist and (optionally) installs it to /Applications.
set -euo pipefail
cd "$(dirname "$0")"

APP="dist/Metron.app"
swift build -c release

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/release/Metron "$APP/Contents/MacOS/Metron"
cp Resources/Info.plist "$APP/Contents/Info.plist"
[ -f Resources/AppIcon.icns ] && cp Resources/AppIcon.icns "$APP/Contents/Resources/"

# Ad-hoc sign so macOS launches it without a Gatekeeper detour.
codesign --force --deep --sign - "$APP" 2>/dev/null || true

echo "Built $APP"
