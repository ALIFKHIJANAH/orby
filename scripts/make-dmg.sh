#!/bin/bash
# Packs build/Orby.app into a drag-to-Applications disk image. Usage: scripts/make-dmg.sh [version]
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="${1:-${VERSION:-0.1.0}}"
APP="build/Orby.app"
OUT="build/release/Orby-${VERSION}.dmg"
VOLUME="Orby ${VERSION}"
[[ -d "$APP" ]] || { echo "Missing $APP, run scripts/build-app.sh first" >&2; exit 1; }

STAGE="$(mktemp -d)"
RW="$(mktemp -u).dmg"
trap 'hdiutil detach "/Volumes/$VOLUME" -quiet 2>/dev/null || true; rm -rf "$STAGE" "$RW"' EXIT

ditto "$APP" "$STAGE/Orby.app"
ln -s /Applications "$STAGE/Applications"

hdiutil create -quiet -volname "$VOLUME" -srcfolder "$STAGE" -fs HFS+ -format UDRW -ov "$RW"
hdiutil attach -quiet -noautoopen "$RW"

# Window layout is cosmetic; a headless machine without Finder still gets a working image.
osascript <<OSA || echo "Finder layout skipped"
tell application "Finder"
  -- Finder learns about a fresh mount a moment after hdiutil returns.
  repeat 40 times
    if exists disk "$VOLUME" then exit repeat
    delay 0.25
  end repeat
  tell disk "$VOLUME"
    open
    set current view of container window to icon view
    set toolbar visible of container window to false
    set statusbar visible of container window to false
    set bounds of container window to {200, 200, 740, 560}
    set opts to icon view options of container window
    set arrangement of opts to not arranged
    set icon size of opts to 128
    set position of item "Orby.app" of container window to {140, 170}
    set position of item "Applications" of container window to {400, 170}
    update without registering applications
    delay 1
    close
  end tell
end tell
OSA

# Volume icon: the file plus the volume's "has custom icon" flag. Added after the Finder pass,
# which otherwise drops it.
cp docs/design/AppIcon.icns "/Volumes/$VOLUME/.VolumeIcon.icns"
SetFile -a C "/Volumes/$VOLUME" 2>/dev/null || xcrun SetFile -a C "/Volumes/$VOLUME" 2>/dev/null || true

sync
hdiutil detach -quiet "/Volumes/$VOLUME"
mkdir -p "$(dirname "$OUT")"
hdiutil convert -quiet "$RW" -format UDZO -imagekey zlib-level=9 -ov -o "$OUT"
echo "Built $OUT"
