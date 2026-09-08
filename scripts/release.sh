#!/usr/bin/env bash
#
# Cut an Expandr release: build → notarize → staple → make the .pkg wizard →
# sign it for Sparkle + generate the appcast → publish to GitHub.
#
# The .pkg is the ONLY artifact users see: fresh installs run it, and Sparkle
# auto-updates install that same .pkg (a Sparkle "package" update, which asks
# for the admin password like any installer). There is no separate .zip.
#
# Prereqs (all one-time):
#   - Developer ID Application + Installer certs in the keychain
#   - notarytool profile stored:  xcrun notarytool store-credentials "$NOTARY_PROFILE" ...
#   - Sparkle keys generated (private key in keychain)
#   - gh authenticated as the repo owner
#
# Usage:  ./scripts/release.sh            # build, notarize, publish a GitHub release
#         ./scripts/release.sh --dry-run  # everything except the GitHub publish
#
# Bump EXPANDR_VERSION in scripts/expandr-release.env before running.

set -Eeuf -o pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO"
# shellcheck source=/dev/null
source "$REPO/scripts/expandr-release.env"

DRY_RUN=0
[[ "${1:-}" == "--dry-run" ]] && DRY_RUN=1

V="$EXPANDR_VERSION"
TAG="v$V"
APP="target/mac/Expandr.app"
ZIP="target/mac/Expandr-$V.zip"           # temporary: only to submit the .app for notarization
PKG="target/mac/Expandr.pkg"           # installer wizard
APPCAST="target/mac/appcast.xml"
SIGN_UPDATE="$REPO/scripts/sparkle-tools/bin/sign_update"
DL_BASE="https://github.com/$GH_REPO/releases/download/$TAG"

notarize() {  # notarize <path-to-.zip-or-.pkg>
  echo "==> Notarizing $1 …"
  xcrun notarytool submit "$1" --keychain-profile "$NOTARY_PROFILE" --wait
}

# 1. Build the fully-signed app (engine + GUI + form + Sparkle).
echo "==> [1/6] Building Expandr.app $V …"
./scripts/build_expandr_app.sh

# 2. Notarize the app (notarytool needs a container, so submit a temporary zip),
#    then staple the ticket onto the .app. The zip is discarded — the stapled
#    app ships inside the .pkg.
echo "==> [2/6] Notarizing the app …"
ditto -c -k --keepParent "$APP" "$ZIP"
notarize "$ZIP"
rm -f "$ZIP"
xcrun stapler staple "$APP"

# 3. Build the .pkg from the stapled app, then notarize + staple it.
echo "==> [3/6] Building + notarizing the installer …"
./scripts/build_pkg.sh
notarize "$PKG"
xcrun stapler staple "$PKG"

# 4. Sign the .pkg for Sparkle and read its signature + length.
echo "==> [4/6] Signing the .pkg for Sparkle …"
SIG_LINE="$("$SIGN_UPDATE" "$PKG")"   # e.g. sparkle:edSignature="…" length="12345"
echo "    $SIG_LINE"

# 5. Generate the appcast.
echo "==> [5/6] Writing appcast.xml …"
cat > "$APPCAST" <<XML
<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle" xmlns:dc="http://purl.org/dc/elements/1.1/">
  <channel>
    <title>Expandr</title>
    <link>$SPARKLE_FEED_URL</link>
    <item>
      <title>Version $V</title>
      <pubDate>$(date -u '+%a, %d %b %Y %H:%M:%S +0000')</pubDate>
      <sparkle:version>$V</sparkle:version>
      <sparkle:shortVersionString>$V</sparkle:shortVersionString>
      <sparkle:minimumSystemVersion>13.0</sparkle:minimumSystemVersion>
      <enclosure url="$DL_BASE/Expandr.pkg" $SIG_LINE sparkle:installationType="package" type="application/octet-stream"/>
    </item>
  </channel>
</rss>
XML

# 6. Publish the GitHub release with the installer, the update archive, and the appcast.
if [[ "$DRY_RUN" == 1 ]]; then
  echo "==> [6/6] --dry-run: skipping GitHub publish."
  echo "artifacts ready: $PKG  $APPCAST"
  exit 0
fi
echo "==> [6/6] Publishing GitHub release $TAG …"
gh release create "$TAG" "$PKG" "$APPCAST" \
  --repo "$GH_REPO" --title "Expandr $V" --target "$(git rev-parse HEAD)" \
  --notes "Expandr $V — download **Expandr.pkg** and open it to install. Existing installs update automatically. (appcast.xml is the auto-update feed; you don't need it.)"
echo "released: https://github.com/$GH_REPO/releases/tag/$TAG"
