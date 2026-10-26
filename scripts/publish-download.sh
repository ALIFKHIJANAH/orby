#!/bin/bash
# Uploads build/release/Orby-X.Y.Z.dmg to R2 and makes it the file the website's /download serves.
# scripts/release.sh calls this; run it alone to retry a failed upload or roll back to an older DMG.
# Usage: scripts/publish-download.sh X.Y.Z
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="${1:?Usage: scripts/publish-download.sh X.Y.Z}"
DMG="build/release/Orby-${VERSION}.dmg"
BUCKET="orby-releases"
[[ -f "$DMG" ]] || { echo "Missing $DMG, run scripts/make-dmg.sh $VERSION first" >&2; exit 1; }

put() {
  npx --yes wrangler@4 r2 object put "$BUCKET/$1" --remote --file "$DMG" \
    --content-type application/x-apple-diskimage \
    --content-disposition "attachment; filename=\"Orby-${VERSION}.dmg\""
}
# The versioned copy is kept for rollbacks; Orby-latest.dmg is what /download streams.
put "Orby-${VERSION}.dmg"
put "Orby-latest.dmg"
echo "/download now serves Orby $VERSION"
