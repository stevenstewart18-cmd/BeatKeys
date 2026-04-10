#!/bin/bash
# make_dmg.sh — builds BeatKeys.dmg with drag-to-install layout
set -e

PROJ="$(cd "$(dirname "$0")" && pwd)"
APP="$PROJ/BeatKeys.app"
DMG_OUT="$PROJ/BeatKeys.dmg"
VOL_NAME="BeatKeys"
STAGING="/tmp/beatkeys_dmg_stage"
RW_DMG="/tmp/beatkeys_rw.dmg"
BG_IMG="$PROJ/dmg_background.png"
CERT="Developer ID Application"

# ── 0. Clean up any leftover mounts from a previous run ──────────────────────
hdiutil detach "/Volumes/$VOL_NAME" -quiet 2>/dev/null || true
rm -f "$RW_DMG"

# ── 1. Build ──────────────────────────────────────────────────────────────────
echo "🔨 Building app..."
"$PROJ/build.sh"

# ── 2. Generate background image ─────────────────────────────────────────────
echo "🎨 Generating DMG background..."
BG_SWIFT=$(mktemp /tmp/beatkeys_bg_XXXXXX.swift)
cat > "$BG_SWIFT" << 'SWIFT_EOF'
#!/usr/bin/swift
import Cocoa

let W = 540, H = 380
let rep = NSBitmapImageRep(
    bitmapDataPlanes: nil,
    pixelsWide: W * 2, pixelsHigh: H * 2,  // 2× retina
    bitsPerSample: 8, samplesPerPixel: 4,
    hasAlpha: true, isPlanar: false,
    colorSpaceName: .calibratedRGB,
    bytesPerRow: 0, bitsPerPixel: 0)!
rep.size = NSSize(width: W, height: H)

NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
NSGraphicsContext.current?.imageInterpolation = .high

let cw = CGFloat(W), ch = CGFloat(H)

// ── Background: dark charcoal ──
NSColor(srgbRed: 0.11, green: 0.11, blue: 0.13, alpha: 1).setFill()
NSBezierPath.fill(NSRect(x: 0, y: 0, width: cw, height: ch))

// ── Subtle vignette gradient ──
let center = NSPoint(x: cw / 2, y: ch / 2)
let radius = max(cw, ch) * 0.75
let gradient = NSGradient(colors: [
    NSColor(white: 0, alpha: 0),
    NSColor(white: 0, alpha: 0.35)
])!
gradient.draw(fromCenter: center, radius: 0,
              toCenter: center, radius: radius,
              options: [])

// ── Helper: draw centered string ──
func draw(_ s: String, font: NSFont, color: NSColor,
          centerX: CGFloat, y: CGFloat) {
    let attrs: [NSAttributedString.Key: Any] = [
        .font: font, .foregroundColor: color]
    let str = NSAttributedString(string: s, attributes: attrs)
    let sz  = str.size()
    str.draw(at: NSPoint(x: centerX - sz.width / 2, y: y))
}

// ── Column X positions ──
let leftX:  CGFloat = cw * 0.27   // app icon center
let rightX: CGFloat = cw * 0.73   // applications center
let iconY:  CGFloat = ch * 0.42   // icon baseline (Finder draws icons above this)

// ── App label ──
draw("BeatKeys.app",
     font: .systemFont(ofSize: 12, weight: .medium),
     color: NSColor(white: 0.75, alpha: 1),
     centerX: leftX, y: iconY - 18)

// ── Applications label ──
draw("Applications",
     font: .systemFont(ofSize: 12, weight: .medium),
     color: NSColor(white: 0.75, alpha: 1),
     centerX: rightX, y: iconY - 18)

// ── Arrow ──
let arrowFont = NSFont.systemFont(ofSize: 40, weight: .ultraLight)
draw("→",
     font: arrowFont,
     color: NSColor(srgbRed: 0.4, green: 0.7, blue: 1.0, alpha: 0.85),
     centerX: cw / 2, y: iconY)

// ── Instruction text — just below the icon labels ──
draw("Drag BeatKeys to Applications to install",
     font: .systemFont(ofSize: 12, weight: .regular),
     color: NSColor(white: 0.5, alpha: 1),
     centerX: cw / 2, y: iconY - 44)

NSGraphicsContext.restoreGraphicsState()

let data = rep.representation(using: .png, properties: [:])!
try! data.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
SWIFT_EOF

swift "$BG_SWIFT" "$BG_IMG"
rm -f "$BG_SWIFT"
echo "   Background saved → $BG_IMG"

# ── 2. Build staging folder ───────────────────────────────────────────────────
echo "📁 Staging DMG contents..."
rm -rf "$STAGING"
mkdir -p "$STAGING"
cp -r "$APP" "$STAGING/"
ln -s /Applications "$STAGING/Applications"

# ── 3. Create writable DMG from staging ──────────────────────────────────────
echo "💿 Creating writable DMG..."
rm -f "$RW_DMG"
hdiutil create \
    -volname   "$VOL_NAME" \
    -srcfolder "$STAGING" \
    -ov \
    -format    UDRW \
    -size      30m \
    "$RW_DMG" > /dev/null

# ── 4. Mount writable DMG ────────────────────────────────────────────────────
echo "🔧 Configuring Finder layout..."
MOUNT_DIR=$(hdiutil attach -readwrite -noverify -noautoopen "$RW_DMG" \
    | awk '/\/Volumes/ { print $NF }' | tail -1)
echo "   Mounted at: $MOUNT_DIR"
sleep 1   # let Finder settle

# ── 5. Copy background into hidden folder ────────────────────────────────────
mkdir -p "$MOUNT_DIR/.background"
cp "$BG_IMG" "$MOUNT_DIR/.background/background.png"

# ── 6. Set Finder window layout via AppleScript ───────────────────────────────
# Window: 540×380, icon size 80, no toolbar/statusbar
osascript - "$VOL_NAME" << 'APPLESCRIPT'
on run argv
    set volName to item 1 of argv
    tell application "Finder"
        tell disk volName
            open
            delay 1
            set current view of container window to icon view
            set toolbar visible of container window to false
            set statusbar visible of container window to false
            set the bounds of container window to {400, 100, 940, 480}
            set viewOptions to the icon view options of container window
            set arrangement of viewOptions to not arranged
            set icon size of viewOptions to 80
            set background picture of viewOptions to file ".background:background.png"
            set position of item "BeatKeys.app" of container window to {146, 185}
            set position of item "Applications" of container window to {394, 185}
            close
            open
            update without registering applications
            delay 3
            close
        end tell
    end tell
end run
APPLESCRIPT

# ── 7. Clean DS_Store metadata ────────────────────────────────────────────────
sync
sleep 1
hdiutil detach "$MOUNT_DIR" -quiet

# ── 8. Convert to read-only compressed DMG ───────────────────────────────────
echo "📦 Compressing DMG..."
rm -f "$DMG_OUT"
hdiutil convert "$RW_DMG" -format UDZO -imagekey zlib-level=9 -o "$DMG_OUT" > /dev/null
rm -f "$RW_DMG"

# ── 9. Sign the DMG ──────────────────────────────────────────────────────────
echo "🔏 Signing DMG..."
codesign --sign "$CERT" "$DMG_OUT"

echo ""
echo "✅ Done!  →  $DMG_OUT"
echo ""
echo "To notarize:"
echo "  xcrun notarytool submit BeatKeys.dmg --keychain-profile \"notary\" --wait"
echo "  xcrun stapler staple BeatKeys.dmg"
