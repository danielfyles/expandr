#!/usr/bin/env bash
#
# Build a signed macOS installer wizard (.pkg) for Expandr.
#
# The wizard walks the user through Introduction → Licence (GPL-3.0) → Install,
# and drops Expandr.app into /Applications. The app registers and starts its
# background engine on first launch, so no install scripts are needed.
#
# Prereq: target/mac/Expandr.app must already be built (scripts/build_expandr_app.sh).
# Output: target/mac/Expandr.pkg

set -Eeuf -o pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO"
# shellcheck source=/dev/null
source "$REPO/scripts/expandr-release.env"

APP="target/mac/Expandr.app"
[[ -d "$APP" ]] || { echo "error: $APP not found — run scripts/build_expandr_app.sh first"; exit 1; }

COMPONENT="target/mac/Expandr-component.pkg"
DIST="target/mac/distribution.xml"
RES="target/mac/pkg-resources"
OUT="target/mac/Expandr.pkg"
STAGE="target/mac/pkgroot"                       # payload root: Expandr.app at top level
CPLIST="target/mac/Expandr-component.plist"

# Build the component from a staged root with an explicit component plist so the
# app bundle is NOT relocatable. By default macOS Installer "relocates": if it finds
# an existing bundle with the same id anywhere (a build checkout, an old copy in
# Downloads), it installs THERE instead of /Applications — which is exactly what
# bit us. Non-relocatable means the payload always lands in /Applications.
echo "==> Building component package (non-relocatable)…"
rm -rf "$STAGE"; mkdir -p "$STAGE"
ditto "$APP" "$STAGE/Expandr.app"
pkgbuild --analyze --root "$STAGE" "$CPLIST" >/dev/null
python3 - "$CPLIST" <<'PLIST'
import plistlib, sys
p = sys.argv[1]
with open(p, "rb") as f: bundles = plistlib.load(f)
def pin(bs):                       # top-level AND nested (ChildBundles) — all non-relocatable
    for b in bs:
        b["BundleIsRelocatable"] = False
        pin(b.get("ChildBundles", []))
pin(bundles)
with open(p, "wb") as f: plistlib.dump(bundles, f)
PLIST
pkgbuild --root "$STAGE" --component-plist "$CPLIST" --install-location /Applications \
  --identifier "app.expandr.pkg" --version "$EXPANDR_VERSION" "$COMPONENT"

echo "==> Preparing wizard resources (GPL licence)…"
rm -rf "$RES"; mkdir -p "$RES"
cp LICENSE "$RES/LICENSE.txt"
cat > "$DIST" <<XML
<?xml version="1.0" encoding="utf-8"?>
<installer-gui-script minSpecVersion="2">
    <title>Expandr</title>
    <license file="LICENSE.txt"/>
    <options customize="never" require-scripts="false" hostArchitectures="arm64"/>
    <volume-check>
        <allowed-os-versions><os-version min="13.0"/></allowed-os-versions>
    </volume-check>
    <choices-outline>
        <line choice="default"><line choice="app.expandr.pkg"/></line>
    </choices-outline>
    <choice id="default"/>
    <choice id="app.expandr.pkg" visible="false">
        <pkg-ref id="app.expandr.pkg"/>
    </choice>
    <pkg-ref id="app.expandr.pkg" version="${EXPANDR_VERSION}" onConclusion="none">Expandr-component.pkg</pkg-ref>
</installer-gui-script>
XML

INSTALLER_ID="$(security find-identity -v 2>/dev/null | awk -F'"' '/Developer ID Installer/ {print $2; exit}')"

echo "==> Building product archive (${INSTALLER_ID:-unsigned})…"
if [[ -n "$INSTALLER_ID" ]]; then
  productbuild --distribution "$DIST" --resources "$RES" \
    --package-path "target/mac" --sign "$INSTALLER_ID" "$OUT"
else
  productbuild --distribution "$DIST" --resources "$RES" \
    --package-path "target/mac" "$OUT"
fi

rm -rf "$COMPONENT" "$STAGE" "$CPLIST"
echo "built: $OUT"
