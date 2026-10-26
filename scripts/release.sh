#!/bin/bash
# Ships a version: builds the app and DMG from a clean HEAD, tags and pushes vX.Y.Z, publishes the
# GitHub release with the DMG and zip, then points the website's /download at the new DMG in R2.
# Usage: scripts/release.sh X.Y.Z [notes.md]   (without notes.md, GitHub generates them)
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="${1:?Usage: scripts/release.sh X.Y.Z [notes.md]}"
NOTES="${2:-}"
TAG="v${VERSION}"
fail() { echo "$1" >&2; exit 1; }

[[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || fail "Version must look like 1.2.3"
[[ -z "$NOTES" || -f "$NOTES" ]] || fail "Missing notes file $NOTES"
[[ -z "$(git status --porcelain)" ]] || fail "Commit or stash your changes first: a release is built from HEAD"
git fetch --tags --quiet origin
git rev-parse -q --verify "refs/tags/$TAG" >/dev/null && fail "$TAG already exists"
# Check both logins before the slow build, so a release never stops halfway on auth.
gh auth status >/dev/null 2>&1 || fail "Not logged in to GitHub, run: gh auth login"
npx --yes wrangler@4 r2 bucket info orby-releases >/dev/null 2>&1 || fail "No access to R2 bucket orby-releases, run: npx wrangler login"

VERSION="$VERSION" scripts/build-app.sh
scripts/make-dmg.sh "$VERSION"
DMG="build/release/Orby-${VERSION}.dmg"
ZIP="build/release/Orby-${VERSION}.zip"
ditto -c -k --keepParent build/Orby.app "$ZIP"

git tag -a "$TAG" -m "Orby $VERSION"
git push origin "$TAG"
SUMS="$(printf '\nSHA-256\n'; for f in "$DMG" "$ZIP"; do printf -- '- `%s` `%s`\n' "$(basename "$f")" "$(shasum -a 256 "$f" | cut -d' ' -f1)"; done)"
if [[ -n "$NOTES" ]]; then
  gh release create "$TAG" "$DMG" "$ZIP" --verify-tag --title "Orby $VERSION" --notes "$(cat "$NOTES")"$'\n'"$SUMS"
else
  gh release create "$TAG" "$DMG" "$ZIP" --verify-tag --title "Orby $VERSION" --generate-notes --notes "$SUMS"
fi

scripts/publish-download.sh "$VERSION"
echo "Released Orby $VERSION"
