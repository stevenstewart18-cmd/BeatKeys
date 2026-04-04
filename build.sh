#!/bin/bash
set -e

PROJ="/Users/steven/BeatLight"
APP="$PROJ/BeatLight.app"
BINARY="$APP/Contents/MacOS/BeatLight"
CERT="Apple Development: steven Stewart (H9TP3263UY)"
ENT="$PROJ/BeatLight.entitlements"

echo "🔨 Compiling BeatLight..."

swiftc \
    "$PROJ/Sources/main.swift" \
    "$PROJ/Sources/AppDelegate.swift" \
    "$PROJ/Sources/AudioEngine.swift" \
    "$PROJ/Sources/KeyboardController.swift" \
    -framework AppKit \
    -framework CoreAudio \
    -framework Accelerate \
    -framework Foundation \
    -o "$PROJ/BeatLight_binary" \
    2>&1

echo "📦 Creating .app bundle..."
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
mkdir -p "$APP/Contents/Resources"

cp "$PROJ/BeatLight_binary" "$BINARY"
cp "$PROJ/Info.plist" "$APP/Contents/Info.plist"
chmod +x "$BINARY"

echo "🔏 Signing with Developer certificate + entitlements..."
codesign --force --sign "$CERT" --options runtime --entitlements "$ENT" "$APP" 2>&1

xattr -dr com.apple.quarantine "$APP" 2>/dev/null || true

echo ""
echo "✅ Done!"
echo "▶️  To run:  open $APP"
echo "📋 To check tap log after 5s:  cat /tmp/beatlight_tap.log"
