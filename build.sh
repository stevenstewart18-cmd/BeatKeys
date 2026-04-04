#!/bin/bash
set -e

PROJ="/Users/steven/Documents/Claude/Projects/BeatKeys"
APP="$PROJ/BeatKeys.app"
BINARY="$APP/Contents/MacOS/BeatKeys"
CERT="Developer ID Application"
ENT="$PROJ/BeatKeys.entitlements"

echo "🔨 Compiling BeatKeys..."

swiftc \
    "$PROJ/Sources/main.swift" \
    "$PROJ/Sources/AppDelegate.swift" \
    "$PROJ/Sources/AudioEngine.swift" \
    "$PROJ/Sources/KeyboardController.swift" \
    -framework AppKit \
    -framework CoreAudio \
    -framework Accelerate \
    -framework Foundation \
    -o "$PROJ/BeatKeys_binary" \
    2>&1

echo "📦 Creating .app bundle..."
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
mkdir -p "$APP/Contents/Resources"

cp "$PROJ/BeatKeys_binary" "$BINARY"
cp "$PROJ/Info.plist" "$APP/Contents/Info.plist"
cp "$PROJ/BeatKeys.icns" "$APP/Contents/Resources/BeatKeys.icns"
chmod +x "$BINARY"

echo "🔏 Signing with Developer certificate + entitlements..."
codesign --force --sign "$CERT" --options runtime --entitlements "$ENT" "$APP" 2>&1

xattr -dr com.apple.quarantine "$APP" 2>/dev/null || true

echo ""
echo "✅ Done!"
echo "▶️  To run:  open $APP"
echo "📋 To check tap log after 5s:  cat /tmp/beatkeys_tap.log"
