#!/bin/bash
# Assembles build/SFTPManager.app from the SwiftPM binary.
#
# This machine has Command Line Tools only, so `xcodebuild` is unavailable and
# the bundle has to be laid out by hand. The ad-hoc signature at the end keeps
# the code-signing identity stable between builds, which is what lets the app
# read back its own Keychain items instead of prompting every launch.
#
#   ./Scripts/make_app.sh                 native arch, release
#   ./Scripts/make_app.sh debug           native arch, debug (keeps symbols)
#   ./Scripts/make_app.sh --universal     arm64 + x86_64, for a release download
set -euo pipefail

cd "$(dirname "$0")/.."
CONFIG=release
UNIVERSAL=0
for arg in "$@"; do
    case "$arg" in
        --universal) UNIVERSAL=1 ;;
        debug|release) CONFIG="$arg" ;;
        *) echo "usage: make_app.sh [debug|release] [--universal]" >&2; exit 2 ;;
    esac
done

APP="build/SFTPManager.app"
# The deployment target has to match Package.swift, or the cross build links
# against a different SDK floor than the native one.
DEPLOYMENT_TARGET=15.0

echo "▸ swift build -c $CONFIG"
swift build -c "$CONFIG"
NATIVE="$(swift build -c "$CONFIG" --show-bin-path)/SFTPManager"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
TARGET="$APP/Contents/MacOS/SFTPManager"

if [ "$UNIVERSAL" = "1" ]; then
    # `swift build --arch a --arch b` needs Xcode's build system, which is not
    # installed here. Building the second slice with an explicit target triple
    # and stitching the two with lipo gets the same result from SwiftPM alone.
    case "$(uname -m)" in
        arm64) OTHER=x86_64 ;;
        x86_64) OTHER=arm64 ;;
        *) echo "unknown host architecture: $(uname -m)" >&2; exit 1 ;;
    esac
    echo "▸ swift build -c $CONFIG (cross to $OTHER)"
    swift build -c "$CONFIG" --scratch-path ".build/$OTHER" \
        -Xswiftc -target -Xswiftc "$OTHER-apple-macos$DEPLOYMENT_TARGET" \
        -Xcc -arch -Xcc "$OTHER"
    echo "▸ lipo $(uname -m) + $OTHER"
    lipo -create "$NATIVE" ".build/$OTHER/$CONFIG/SFTPManager" -output "$TARGET"
else
    cp "$NATIVE" "$TARGET"
fi

if [ "$CONFIG" = "release" ]; then
    # Roughly halves the binary. Must happen before codesign — stripping a
    # signed binary invalidates the signature. Debug builds keep their symbols.
    BEFORE=$(stat -f%z "$TARGET")
    strip -rSTx "$TARGET"
    AFTER=$(stat -f%z "$TARGET")
    echo "▸ strip: $((BEFORE / 1048576))MB → $((AFTER / 1048576))MB"
fi

cp Resources/Info.plist "$APP/Contents/Info.plist"
printf 'APPL????' > "$APP/Contents/PkgInfo"

if [ -f Resources/AppIcon.icns ]; then
    cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
else
    echo "▸ no Resources/AppIcon.icns — run Scripts/make_icon.sh first (optional)"
fi

echo "▸ codesign (ad-hoc)"
codesign --force --deep --sign - "$APP"
codesign --verify --deep --strict "$APP"

echo "✓ $APP ($(lipo -archs "$TARGET"))"
