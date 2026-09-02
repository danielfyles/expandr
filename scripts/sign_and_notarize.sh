#!/usr/bin/env bash
#
# Sign (Developer ID) + notarize + staple Expandr.app, then package a DMG and
# notarize + staple that too. This is the release path for distribution OUTSIDE
# the App Store (direct download / Homebrew cask).
#
# PREREQUISITES (all require YOUR Apple Developer Program membership — I can't
# do these for you; they involve your Apple credentials):
#   1. Join the Apple Developer Program ($99/yr).
#   2. Create a "Developer ID Application" certificate and install it in your
#      login keychain (Xcode > Settings > Accounts, or developer.apple.com).
#      Find its name with:  security find-identity -v -p codesigning
#   3. Store notarytool credentials once (uses an app-specific password or an
#      App Store Connect API key):
#        xcrun notarytool store-credentials expandr-notary \
#          --apple-id "you@example.com" --team-id "TEAMID" \
#          --password "app-specific-password"
#
# Usage:
#   DEVID="Developer ID Application: Your Name (TEAMID)" \
#   NOTARY_PROFILE=expandr-notary \
#   ./scripts/sign_and_notarize.sh [path/to/Expandr.app]

set -Eeuf -o pipefail

APP="${1:-target/mac/Expandr.app}"
ENTITLEMENTS="scripts/entitlements.plist"
NOTARY_PROFILE="${NOTARY_PROFILE:-expandr-notary}"
EXE="$APP/Contents/MacOS/espanso"

: "${DEVID:?set DEVID to your 'Developer ID Application: NAME (TEAMID)' identity (see: security find-identity -v -p codesigning)}"
[ -d "$APP" ] || { echo "error: $APP not found — run scripts/create_bundle.sh first"; exit 1; }

echo "==> signing $APP with hardened runtime"
# The bundle has a single Mach-O (static build, no nested frameworks): sign the
# executable, then the bundle. Add nested-signing here if that ever changes.
codesign --force --timestamp --options runtime \
  --entitlements "$ENTITLEMENTS" -s "$DEVID" "$EXE"
codesign --force --timestamp --options runtime \
  --entitlements "$ENTITLEMENTS" -s "$DEVID" "$APP"
codesign --verify --strict --verbose=2 "$APP"

echo "==> notarizing the app"
# Notarize the app first (zip it for submission), staple the ticket back.
appzip="$(mktemp -d)/Expandr.zip"
ditto -c -k --sequesterRsrc --keepParent "$APP" "$appzip"
xcrun notarytool submit "$appzip" --keychain-profile "$NOTARY_PROFILE" --wait
xcrun stapler staple "$APP"

echo "==> building + notarizing the DMG"
dmg_line="$(./scripts/create_dmg.sh "$APP")"; echo "$dmg_line"
DMG="${dmg_line#created }"
codesign --force --timestamp -s "$DEVID" "$DMG"
xcrun notarytool submit "$DMG" --keychain-profile "$NOTARY_PROFILE" --wait
xcrun stapler staple "$DMG"

echo "==> done"
xcrun stapler validate "$DMG" && echo "DMG stapled + valid: $DMG"
spctl --assess --type open --context context:primary-signature -vv "$DMG" || true
