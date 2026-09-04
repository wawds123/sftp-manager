#!/bin/bash
# Assembles build/SFTPManager.app from the SwiftPM binary.
#
# This machine has Command Line Tools only, so `xcodebuild` is unavailable and
# the bundle has to be laid out by hand. The ad-hoc signature at the end keeps
# the code-signing identity stable between builds, which is what lets the app
# read back its own Keychain items instead of prompting every launch.
set -euo pipefail

cd "$(dirname "$0")/.."
CONFIG="${1:-release}"
APP="build/SFTPManager.app"

echo "▸ swift build -c $CONFIG"
swift build -c "$CONFIG"
BIN="$(swift build -c "$CONFIG" --show-bin-path)/SFTPManager"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

cp "$BIN" "$APP/Contents/MacOS/SFTPManager"
cp Resources/Info.plist "$APP/Contents/Info.plist"
printf 'APPL????' > "$APP/Contents/PkgInfo"

if [ -f Resources/AppIcon.icns ]; then
    cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
else
    echo "▸ no Resources/AppIcon.icns — run Scripts/make_icon.sh first (optional)"
fi

echo "▸ codesign (ad-hoc)"
codesign --force --deep --sign - "$APP"

echo "✓ $APP"
