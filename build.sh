#!/bin/bash
# Builds Metron.app into ./dist.
#
#   ./build.sh                    arm64, ad-hoc signed — the fast local loop
#   METRON_UNIVERSAL=1 ./build.sh arm64 + x86_64, for something you hand out
#   METRON_SIGN_ID="Developer ID Application: ..." ./build.sh   real signature
#
# Then: cp -R dist/Metron.app /Applications/ && open -a Metron
set -euo pipefail
cd "$(dirname "$0")"

APP="dist/Metron.app"
UNIVERSAL=${METRON_UNIVERSAL:-0}
SIGN_ID=${METRON_SIGN_ID:--}

if [[ "$UNIVERSAL" == 1 ]]; then
  swift build -c release --arch arm64 --arch x86_64
  BIN=.build/apple/Products/Release/Metron
else
  swift build -c release
  BIN=.build/release/Metron
fi

[[ -f "$BIN" ]] || { echo "no binary at $BIN" >&2; exit 1; }

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/Metron"
cp Resources/Info.plist "$APP/Contents/Info.plist"
if [[ -f Resources/AppIcon.icns ]]; then
  cp Resources/AppIcon.icns "$APP/Contents/Resources/"
fi

# Stamp the version from the git tag when there is one, so a downloaded build
# can be told apart from the one someone built themselves. Falls back to
# whatever Info.plist already says.
VERSION=$(git describe --tags --abbrev=0 2>/dev/null || true)
VERSION=${VERSION#v}
# Only a plain dotted number is a legal CFBundleShortVersionString; a tag like
# "1.0-working" is not, and Launch Services quietly rejects the whole bundle.
if [[ "$VERSION" =~ ^[0-9]+(\.[0-9]+){0,2}$ ]]; then
  /usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" \
    "$APP/Contents/Info.plist"
  /usr/libexec/PlistBuddy -c "Set :CFBundleVersion $(git rev-list --count HEAD)" \
    "$APP/Contents/Info.plist"
fi

# Sign. `-` is an ad-hoc signature, which is enough for macOS to launch a
# bundle you built yourself. A signing failure is reported rather than
# swallowed: an unsigned bundle fails to launch later with no explanation,
# which is a much worse place to find out.
#
# --deep is deprecated and unnecessary here: the bundle has no nested code,
# just the one executable.
codesign --force --options runtime --sign "$SIGN_ID" "$APP"

echo "Built $APP"
codesign -dv "$APP" 2>&1 | grep -E '^(Format|Signature|Identifier)' || true
