#!/bin/bash
# Build Pomodoro.app, wrap it in a .dmg, and install it to /Applications.
# Usage: tools/make_app.sh                      (version from the VERSION file)
#        TEST=1 tools/make_app.sh               (build/Pomodoro Test.app, id com.aniketnamjoshi.pomodoro.test, not installed:
#                                                for real runs that never touch the installed copy)
set -euo pipefail
cd "$(dirname "$0")/.."
# The default SDK symlink points at macOS 27, newer than this Swift compiler; 26.5 matches it.
export SDKROOT=/Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk
VERSION=$(cat VERSION)
BUILD=$(git rev-list --count HEAD 2>/dev/null || echo 1)
NAME="Pomodoro"; ID=com.aniketnamjoshi.pomodoro
if [ "${TEST:-0}" = "1" ]; then NAME="Pomodoro Test"; ID=com.aniketnamjoshi.pomodoro.test; NO_INSTALL=1; fi
OUT=build; APP="$OUT/$NAME.app"
rm -rf "$APP"; mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

swift run pomodoro-check
# Universal: Apple silicon and Intel, built separately and fused with lipo (UNIVERSAL=0 skips Intel for quick local builds).
swift build -c release --product Pomodoro && swift build -c release --product tomo
BIN="$(swift build -c release --show-bin-path)/Pomodoro"
if [ "${UNIVERSAL:-1}" = "1" ]; then
  swift build -c release --product Pomodoro --triple x86_64-apple-macosx14.0
  swift build -c release --product tomo --triple x86_64-apple-macosx14.0
  X86=".build/x86_64-apple-macosx/release"
  lipo -create "$BIN" "$X86/Pomodoro" -output "$APP/Contents/MacOS/Pomodoro"
  lipo -create "$(dirname "$BIN")/tomo" "$X86/tomo" -output "$APP/Contents/MacOS/tomo"
else
  cp "$BIN" "$APP/Contents/MacOS/Pomodoro"; cp "$(dirname "$BIN")/tomo" "$APP/Contents/MacOS/tomo"
fi
lipo -info "$APP/Contents/MacOS/Pomodoro"

# Icon: Tomo drawn by the app itself
ICONSET=$OUT/Pomodoro.iconset; rm -rf "$ICONSET"; mkdir -p "$ICONSET"
"$BIN" --icon "$OUT/icon_1024.png"
for s in 16 32 128 256 512; do
  sips -z $s $s "$OUT/icon_1024.png" --out "$ICONSET/icon_${s}x${s}.png" >/dev/null
  sips -z $((s*2)) $((s*2)) "$OUT/icon_1024.png" --out "$ICONSET/icon_${s}x${s}@2x.png" >/dev/null
done
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/Pomodoro.icns"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleName</key><string>$NAME</string>
  <key>CFBundleDisplayName</key><string>$NAME</string>
  <key>CFBundleIdentifier</key><string>$ID</string>
  <key>CFBundleExecutable</key><string>Pomodoro</string>
  <key>CFBundleIconFile</key><string>Pomodoro</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>$VERSION</string>
  <key>CFBundleVersion</key><string>$BUILD</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>LSUIElement</key><true/>
  <key>LSApplicationCategoryType</key><string>public.app-category.productivity</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSAppleEventsUsageDescription</key><string>Pomodoro reads the address and title of your front Chrome tab, only during a session, to check it fits your task. Nothing leaves your Mac.</string>
  <key>NSHumanReadableCopyright</key><string>Copyright 2026 Aniket Namjoshi</string>
</dict></plist>
PLIST
plutil -lint "$APP/Contents/Info.plist" >/dev/null
# Same stable identity as SpeakFit and JARVIS, so any permission survives rebuilds.
IDENTITY=$(security find-identity -v -p codesigning | awk -F'"' '/JARVIS Dev/{print $2; exit}')
codesign --force --sign "${IDENTITY:--}" --identifier "$ID.tomo" "$APP/Contents/MacOS/tomo"   # helpers are signed before the app
codesign --force --sign "${IDENTITY:--}" --identifier "$ID" "$APP"
codesign --verify --strict "$APP"

if [ "${NO_INSTALL:-0}" = "1" ]; then echo "Built $NAME $VERSION ($BUILD) at $APP (not installed)"; exit 0; fi

STAGE=$OUT/dmg; rm -rf "$STAGE"; mkdir -p "$STAGE"; cp -R "$APP" "$STAGE/"; ln -s /Applications "$STAGE/Applications"
DMG=dist/Pomodoro-$VERSION.dmg; mkdir -p dist; rm -f "$DMG"
if [ "${RELEASE:-0}" = "1" ]; then
  # Release disk image: the drag-to-Applications window (app left, Applications right, an arrow between,
  # the first-open step at the bottom), laid out by Finder on a writable image, then compressed.
  VOL="Pomodoro $VERSION"; RW=$OUT/rw.dmg; rm -f "$RW"
  mkdir -p "$STAGE/.background"
  "$APP/Contents/MacOS/Pomodoro" --dmg-background "$OUT/bg"
  tiffutil -cathidpicheck "$OUT/bg.png" "$OUT/bg@2x.png" -out "$STAGE/.background/background.tiff" >/dev/null
  hdiutil create -volname "$VOL" -srcfolder "$STAGE" -ov -format UDRW -fs HFS+ "$RW" >/dev/null
  DEV=$(hdiutil attach -readwrite -noverify -noautoopen "$RW" | awk '/Apple_HFS/{print $1}')
  sleep 1
  osascript <<OSA
with timeout of 30 seconds
tell application "Finder"
  tell disk "$VOL"
    open
    set current view of container window to icon view
    set toolbar visible of container window to false
    set statusbar visible of container window to false
    set bounds of container window to {200, 120, 840, 590}   -- 420 pt of background plus the title and status bars
    set o to the icon view options of container window
    set arrangement of o to not arranged
    set icon size of o to 112
    set text size of o to 13
    set background picture of o to file ".background:background.tiff"
    set position of item "Pomodoro.app" of container window to {170, 225}
    set position of item "Applications" of container window to {470, 225}
    update without registering applications
    delay 1
    close
  end tell
end tell
end timeout
OSA
  chmod -Rf go-w "/Volumes/$VOL" 2>/dev/null || true
  sync; hdiutil detach "$DEV" >/dev/null
  hdiutil convert "$RW" -format UDZO -imagekey zlib-level=9 -o "$DMG" >/dev/null; rm -f "$RW"
  hdiutil verify "$DMG" >/dev/null
  echo "Release disk image: $DMG"; exit 0
fi
hdiutil create -volname "Pomodoro $VERSION" -srcfolder "$STAGE" -ov -format UDZO "$DMG" >/dev/null
hdiutil verify "$DMG" >/dev/null

osascript -e 'with timeout of 5 seconds' -e 'tell application "Pomodoro" to quit' -e 'end timeout' 2>/dev/null || true
sleep 1; pkill -x Pomodoro 2>/dev/null || true
MNT=$(mktemp -d); hdiutil attach -nobrowse -readonly -mountpoint "$MNT" "$DMG" >/dev/null
rm -rf /Applications/Pomodoro.app; cp -R "$MNT/Pomodoro.app" /Applications/
hdiutil detach "$MNT" >/dev/null
echo "Installed Pomodoro $VERSION ($BUILD) from $DMG"
