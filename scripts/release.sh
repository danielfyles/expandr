#!/usr/bin/env bash
#
# Cut an Expandr release: build → notarize → staple → make the .pkg wizard and
# the Sparkle update archive → sign + generate the appcast → publish to GitHub.
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
ZIP="target/mac/Expandr-$V.zip"           # Sparkle update archive
PKG="target/mac/Expandr-$V.pkg"           # installer wizard
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

# 2. Notarize the app (submit a zip), then staple the ticket onto the .app.
echo "==> [2/6] Notarizing the app …"
ditto -c -k --keepParent "$APP" "$ZIP"
notarize "$ZIP"
xcrun stapler staple "$APP"
# Re-zip the *stapled* app — this is the archive Sparkle downloads.
rm -f "$ZIP"; ditto -c -k --keepParent "$APP" "$ZIP"

# 3. Build the .pkg from the stapled app, then notarize + staple it.
echo "==> [3/6] Building + notarizing the installer …"
./scripts/build_pkg.sh
notarize "$PKG"
xcrun stapler staple "$PKG"

# 4. Sign the Sparkle archive and read its signature + length.
echo "==> [4/6] Signing the update archive …"
SIG_LINE="$("$SIGN_UPDATE" "$ZIP")"   # e.g. sparkle:edSignature="…" length="12345"
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
      <enclosure url="$DL_BASE/Expandr-$V.zip" $SIG_LINE type="application/octet-stream"/>
    </item>
  </channel>
</rss>
XML

# 6. Publish the GitHub release with the installer, the update archive, and the appcast.
if [[ "$DRY_RUN" == 1 ]]; then
  echo "==> [6/6] --dry-run: skipping GitHub publish."
  echo "artifacts ready: $PKG  $ZIP  $APPCAST"
  exit 0
fi
echo "==> [6/6] Publishing GitHub release $TAG …"
gh release create "$TAG" "$PKG" "$ZIP" "$APPCAST" \
  --repo "$GH_REPO" --title "Expandr $V" \
  --notes "Expandr $V. Download the .pkg to install; existing installs update automatically via Sparkle."
echo "released: https://github.com/$GH_REPO/releases/tag/$TAG"
