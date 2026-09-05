#!/usr/bin/env bash
#
# Build the unified, shippable Expandr.app (Apple Silicon).
#
# One bundle contains everything:
#   Contents/MacOS/ExpandrSnippets   the Dock GUI (the app you open)   <- main executable
#   Contents/MacOS/espanso           the text-expansion engine (run by launchd)
#   Contents/Helpers/ExpandrForm.app the native form/choice renderer
#
# The GUI registers and manages the background service (a launchd agent that runs
# the nested `espanso` binary). Shipping it as a single bundle lets Sparkle update
# the whole product atomically.
#
# Usage:
#   ./scripts/build_expandr_app.sh                 # assemble + sign (Developer ID if available, else ad-hoc)
#   ./scripts/build_expandr_app.sh --build-engine  # also (re)compile the arm64 engine first
#
# Output: target/mac/Expandr.app

set -Eeuf -o pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO"
# shellcheck source=/dev/null
source "$REPO/scripts/expandr-release.env"

APP="target/mac/Expandr.app"
ENGINE_BIN="target/release/espanso"   # arm64 host build
BUILD_ENGINE=0
[[ "${1:-}" == "--build-engine" ]] && BUILD_ENGINE=1

# --- 1. Engine (Rust) ---------------------------------------------------------
if [[ "$BUILD_ENGINE" == 1 || ! -x "$ENGINE_BIN" ]]; then
  echo "==> Building espanso engine (arm64, release, native — no wxWidgets)…"
  cargo build -p espanso --release --no-default-features --features native-tls
fi
[[ -x "$ENGINE_BIN" ]] || { echo "error: engine binary not found at $ENGINE_BIN"; exit 1; }

# --- 2. Swift GUI + form renderer --------------------------------------------
echo "==> Building ExpandrSnippets (release)…"
swift build -c release --package-path expandr-app
GUI_BIN="expandr-app/.build/release/ExpandrSnippets"

echo "==> Building ExpandrForm helper…"
( cd expandr-app && ./build-form-app.sh >/dev/null )
FORM_APP="expandr-app/build/ExpandrForm.app"

# --- 3. Assemble the bundle ---------------------------------------------------
echo "==> Assembling $APP…"
rm -rf -- "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$APP/Contents/Helpers"

cp "$GUI_BIN"    "$APP/Contents/MacOS/ExpandrSnippets"
cp "$ENGINE_BIN" "$APP/Contents/MacOS/espanso"
cp -R "$FORM_APP" "$APP/Contents/Helpers/ExpandrForm.app"

cp -f espanso/src/res/macos/icon.icns "$APP/Contents/Resources/icon.icns"
mkdir -p "$APP/Contents/Resources/Fonts"
cp espanso-ui/fonts/Fraunces.ttf  "$APP/Contents/Resources/Fonts/"
cp espanso-ui/fonts/Newsreader.ttf "$APP/Contents/Resources/Fonts/"
[[ -f expandr-app/Resources/offline-fix.png ]] && \
  cp expandr-app/Resources/offline-fix.png "$APP/Contents/Resources/offline-fix.png"

echo "APPL????" > "$APP/Contents/PkgInfo"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key>               <string>Expandr</string>
  <key>CFBundleDisplayName</key>        <string>Expandr</string>
  <key>CFBundleIdentifier</key>         <string>${BUNDLE_ID}</string>
  <key>CFBundleExecutable</key>         <string>ExpandrSnippets</string>
  <key>CFBundlePackageType</key>        <string>APPL</string>
  <key>CFBundleShortVersionString</key> <string>${EXPANDR_VERSION}</string>
  <key>CFBundleVersion</key>            <string>${EXPANDR_VERSION}</string>
  <key>CFBundleIconFile</key>           <string>icon</string>
  <key>NSPrincipalClass</key>           <string>NSApplication</string>
  <key>NSHighResolutionCapable</key>    <true/>
  <key>LSMinimumSystemVersion</key>     <string>13.0</string>
  <key>NSHumanReadableCopyright</key>   <string>Expandr — a fork of espanso (© Federico Terzi). GPL-3.0. Fork © 2026 Daniel Fyles.</string>
</dict>
</plist>
PLIST

# --- 4. Code signing (inside-out) --------------------------------------------
# Developer ID if a cert is present (needed for distribution + notarization),
# otherwise ad-hoc so the bundle at least runs locally for testing.
DEVID_ID="$(security find-identity -v -p codesigning 2>/dev/null | awk -F'"' '/Developer ID Application/ {print $2; exit}')"
ENTITLEMENTS="$REPO/scripts/entitlements.plist"

sign() {  # sign <path>
  if [[ -n "$DEVID_ID" ]]; then
    codesign --force --options runtime --timestamp \
      --entitlements "$ENTITLEMENTS" -s "$DEVID_ID" "$1"
  else
    codesign --force -s - "$1"
  fi
}

echo "==> Signing (${DEVID_ID:-ad-hoc})…"
# Inside-out: helper app's inner Mach-O, the helper app, the engine binary, the
# GUI binary, then the outer bundle.
sign "$APP/Contents/Helpers/ExpandrForm.app/Contents/MacOS/ExpandrForm"
sign "$APP/Contents/Helpers/ExpandrForm.app"
sign "$APP/Contents/MacOS/espanso"
sign "$APP/Contents/MacOS/ExpandrSnippets"
sign "$APP"

echo "==> Verifying signature…"
codesign --verify --deep --strict --verbose=2 "$APP" 2>&1 | tail -3 || true

echo "built: $APP  (version ${EXPANDR_VERSION}, ${DEVID_ID:-ad-hoc})"
