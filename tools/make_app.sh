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
swift build -c release --product Pomodoro
BIN="$(swift build -c release --show-bin-path)/Pomodoro"
cp "$BIN" "$APP/Contents/MacOS/Pomodoro"

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
  <key>LSMinimumSystemVersion</key><string>26.0</string>
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
codesign --force --sign "${IDENTITY:--}" --identifier "$ID" "$APP"
codesign --verify --strict "$APP"

if [ "${NO_INSTALL:-0}" = "1" ]; then echo "Built $NAME $VERSION ($BUILD) at $APP (not installed)"; exit 0; fi

STAGE=$OUT/dmg; rm -rf "$STAGE"; mkdir -p "$STAGE"; cp -R "$APP" "$STAGE/"; ln -s /Applications "$STAGE/Applications"
DMG=dist/Pomodoro-$VERSION.dmg; mkdir -p dist; rm -f "$DMG"
hdiutil create -volname "Pomodoro $VERSION" -srcfolder "$STAGE" -ov -format UDZO "$DMG" >/dev/null
hdiutil verify "$DMG" >/dev/null

osascript -e 'with timeout of 5 seconds' -e 'tell application "Pomodoro" to quit' -e 'end timeout' 2>/dev/null || true
sleep 1; pkill -x Pomodoro 2>/dev/null || true
MNT=$(mktemp -d); hdiutil attach -nobrowse -readonly -mountpoint "$MNT" "$DMG" >/dev/null
rm -rf /Applications/Pomodoro.app; cp -R "$MNT/Pomodoro.app" /Applications/
hdiutil detach "$MNT" >/dev/null
echo "Installed Pomodoro $VERSION ($BUILD) from $DMG"
