#!/usr/bin/env bash
#
# Package Expandr.app into a distributable drag-to-Applications .dmg.
#
# Works standalone (no Apple account needed) — but a DMG is only launchable
# without Gatekeeper warnings once the .app inside is signed with a
# "Developer ID Application" cert AND notarized. See sign_and_notarize.sh.
#
# Usage:  ./scripts/create_dmg.sh [path/to/Expandr.app]
#   defaults to target/mac/Expandr.app (produced by create_bundle.sh)

set -Eeuf -o pipefail

APP="${1:-target/mac/Expandr.app}"
VOL_NAME="Expandr"
VERSION="$(awk -F '"' '/^version/ { print $2; exit }' espanso/Cargo.toml)"
OUT="target/mac/Expandr-${VERSION}.dmg"

[ -d "$APP" ] || { echo "error: $APP not found — run scripts/create_bundle.sh first"; exit 1; }

stage="$(mktemp -d)"
trap 'rm -rf "$stage"' EXIT

cp -R "$APP" "$stage/"
ln -s /Applications "$stage/Applications"   # drag target

rm -f "$OUT"
mkdir -p "$(dirname "$OUT")"
hdiutil create \
  -volname "$VOL_NAME" \
  -srcfolder "$stage" \
  -fs HFS+ \
  -format UDZO \
  -ov \
  "$OUT" >/dev/null

echo "created $OUT"
