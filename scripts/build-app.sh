#!/bin/bash
# Builds build/Orby.app (release, ad-hoc signed). Usage: scripts/build-app.sh [--open]
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="${VERSION:-0.1.0}"
APP="build/Orby.app"

swift build -c release --product Orby
swift build -c release --product orby-bridge
BIN="$(swift build -c release --show-bin-path)"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Helpers" "$APP/Contents/Resources"
cp "$BIN/Orby" "$APP/Contents/MacOS/Orby"
cp "$BIN/orby-bridge" "$APP/Contents/Helpers/orby-bridge"
cp docs/design/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>Orby</string>
  <key>CFBundleDisplayName</key><string>Orby</string>
  <key>CFBundleIdentifier</key><string>dev.orby.app</string>
  <key>CFBundleExecutable</key><string>Orby</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>${VERSION}</string>
  <key>CFBundleVersion</key><string>${VERSION}</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>LSUIElement</key><true/>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSAppleEventsUsageDescription</key>
  <string>Orby controls terminal apps (iTerm2, Terminal) to bring the right window, tab and session forward when you click an agent.</string>
</dict>
</plist>
PLIST

codesign --force --sign - "$APP/Contents/Helpers/orby-bridge"
codesign --force --sign - "$APP"
echo "Built $APP"

if [[ "${1:-}" == "--open" ]]; then open "$APP"; fi
