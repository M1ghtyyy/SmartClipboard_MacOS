#!/bin/bash
# Builds build/SmartClipBoard.app from source with Apple's Command Line Tools (Xcode not needed).
#   --clean   delete previous build products first
set -euo pipefail
cd "$(dirname "$0")/.."
source scripts/config.sh

if [ "${1:-}" = "--clean" ]; then
    rm -rf .build build
fi

if ! xcode-select -p >/dev/null 2>&1; then
    echo "Apple's Command Line Tools are not installed."
    echo "Install them with:  xcode-select --install"
    echo "then run this script again."
    exit 1
fi

macos_major="$(sw_vers -productVersion | cut -d. -f1)"
if [ "$macos_major" -lt 14 ]; then
    echo "$APP_NAME needs macOS 14 Sonoma or later (this Mac has $(sw_vers -productVersion))."
    exit 1
fi

echo "Building $APP_NAME (the first build takes about a minute)..."
swift build -c release
BIN_DIR="$(swift build -c release --show-bin-path)"

APP="build/$APP_NAME.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/$APP_NAME" "$APP/Contents/MacOS/$APP_NAME"
cp Resources/Info.plist "$APP/Contents/Info.plist"

# Ad-hoc signature: enough for an app built and run on the same Mac.
codesign --force --sign - --timestamp=none "$APP"

echo "Built $APP"
