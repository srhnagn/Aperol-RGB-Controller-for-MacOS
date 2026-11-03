#!/bin/zsh
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 Aperol

set -euo pipefail
cd "$(dirname "$0")"

APP_NAME="Aperol RGB Controller"
BUNDLE_ID="com.serhanagan.aperol-rgb"
STAGE_DIR="build/stage"
APP_BUNDLE="$STAGE_DIR/$APP_NAME.app"

INSTALL=0
for arg in "$@"; do
    case "$arg" in
        --install) INSTALL=1 ;;
    esac
done

echo "▸ Compiling Aperol RGB Controller for Apple Silicon (macOS 14+)..."
mkdir -p build/stage "$STAGE_DIR"

swiftc -O \
    -target arm64-apple-macosx14.0 \
    -sdk "$(xcrun --show-sdk-path)" \
    -framework AppKit \
    -framework SwiftUI \
    -framework IOKit \
    -framework Foundation \
    Sources/Aperol/App.swift \
    Sources/Aperol/AperolK70Service.swift \
    Sources/Aperol/ContentView.swift \
    -o "build/Aperol"

echo "▸ Assembling App Bundle..."
rm -rf "$APP_BUNDLE"
mkdir -p "$APP_BUNDLE/Contents/MacOS"
mkdir -p "$APP_BUNDLE/Contents/Resources"

cp "build/Aperol" "$APP_BUNDLE/Contents/MacOS/Aperol"
if [ -f "Resources/AppIcon.icns" ]; then
    cp "Resources/AppIcon.icns" "$APP_BUNDLE/Contents/Resources/AppIcon.icns"
fi

cat <<EOF > "$APP_BUNDLE/Contents/Info.plist"
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>Aperol</string>
    <key>CFBundleIdentifier</key>
    <string>$BUNDLE_ID</string>
    <key>CFBundleName</key>
    <string>$APP_NAME</string>
    <key>CFBundleDisplayName</key>
    <string>$APP_NAME</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>NSHighResolutionCapable</key>
    <true/>
</dict>
</plist>
EOF

echo "▸ Signing Bundle..."
codesign --force --deep --sign - "$APP_BUNDLE"

echo "✓ Bundle ready: $APP_BUNDLE"

if [[ "$INSTALL" -eq 1 ]]; then
    echo "▸ Installing into /Applications..."
    rm -rf "/Applications/$APP_NAME.app"
    cp -R "$APP_BUNDLE" "/Applications/$APP_NAME.app"
    echo "✓ Installed: /Applications/$APP_NAME.app"
fi
