#!/usr/bin/env bash
#
# Build the unified, shippable Expandr.app (Apple Silicon).
#
# One bundle contains everything:
#   Contents/MacOS/ExpandrSnippets           the Dock GUI (the app you open)  <- main executable
#   Contents/Helpers/Expandr Agent.app       the background text-expansion agent (run by launchd)
#   Contents/Helpers/ExpandrForm.app         the native form/choice renderer
#
# The GUI registers and manages the background service (a launchd agent that runs
# the nested Expandr Agent binary). Shipping it as a single bundle lets Sparkle
# update the whole product atomically.
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
echo "==> Assembling ${APP}…"
rm -rf -- "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$APP/Contents/Helpers"

cp "$GUI_BIN" "$APP/Contents/MacOS/ExpandrSnippets"

# The engine goes in its OWN nested sub-app ("Expandr Agent") with its own bundle
# id, so it doesn't claim the outer app's LaunchServices identity (which would
# make `open` poke the background agent instead of launching the GUI window). The
# folder name is what macOS shows in Login Items & Extensions.
AGENT_APP="$APP/Contents/Helpers/Expandr Agent.app"
mkdir -p "$AGENT_APP/Contents/MacOS" "$AGENT_APP/Contents/Resources"
cp "$ENGINE_BIN" "$AGENT_APP/Contents/MacOS/espanso"
cp -f espanso/src/res/macos/icon.icns "$AGENT_APP/Contents/Resources/icon.icns"
echo "APPL????" > "$AGENT_APP/Contents/PkgInfo"
cat > "$AGENT_APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key>               <string>Expandr Agent</string>
  <key>CFBundleDisplayName</key>        <string>Expandr Agent</string>
  <key>CFBundleIdentifier</key>         <string>${BUNDLE_ID}.agent</string>
  <key>CFBundleExecutable</key>         <string>espanso</string>
  <key>CFBundleIconFile</key>           <string>icon</string>
  <key>CFBundlePackageType</key>        <string>APPL</string>
  <key>CFBundleShortVersionString</key> <string>${EXPANDR_VERSION}</string>
  <key>CFBundleVersion</key>            <string>${EXPANDR_VERSION}</string>
  <key>LSUIElement</key>                <true/>
  <key>LSBackgroundOnly</key>           <true/>
</dict>
</plist>
PLIST

# ExpandrForm stays in the outer Helpers; the engine finds it there.
cp -R "$FORM_APP" "$APP/Contents/Helpers/ExpandrForm.app"

# Embed Sparkle.framework (auto-update) and point the GUI's rpath at it.
mkdir -p "$APP/Contents/Frameworks"
cp -R "expandr-app/.build/release/Sparkle.framework" "$APP/Contents/Frameworks/"
install_name_tool -add_rpath "@executable_path/../Frameworks" \
  "$APP/Contents/MacOS/ExpandrSnippets" 2>/dev/null || true

cp -f espanso/src/res/macos/icon.icns "$APP/Contents/Resources/icon.icns"

# Localization: copy each <lang>.lproj/Localizable.strings into Contents/Resources
# so Bundle.main resolves the SwiftUI / NSLocalizedString keys. Uses find rather
# than a glob because `set -f` above disables globbing. Adding a language is just
# adding a folder under expandr-app/Localization/ExpandrSnippets/.
[[ -d expandr-app/Localization/ExpandrSnippets ]] && \
  find expandr-app/Localization/ExpandrSnippets -maxdepth 1 -name '*.lproj' \
    -exec cp -R {} "$APP/Contents/Resources/" \;
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
  <key>CFBundleDevelopmentRegion</key>  <string>en</string>
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
  <key>SUFeedURL</key>                  <string>${SPARKLE_FEED_URL}</string>
  <key>SUPublicEDKey</key>              <string>${SPARKLE_PUBLIC_KEY}</string>
  <key>SUEnableAutomaticChecks</key>    <true/>
</dict>
</plist>
PLIST

# --- 4. Code signing (inside-out) --------------------------------------------
# Developer ID if a cert is present (needed for distribution + notarization),
# otherwise ad-hoc so the bundle at least runs locally for testing.
DEVID_ID="$(security find-identity -v -p codesigning 2>/dev/null | awk -F'"' '/Developer ID Application/ {print $2; exit}')"
ENTITLEMENTS="$REPO/scripts/entitlements.plist"

sign() {  # our own code — hardened runtime + app entitlements
  if [[ -n "$DEVID_ID" ]]; then
    codesign --force --options runtime --timestamp \
      --entitlements "$ENTITLEMENTS" -s "$DEVID_ID" "$1"
  else
    codesign --force -s - "$1"
  fi
}

sign_helper() {  # third-party helpers (Sparkle) — hardened runtime, no app entitlements
  if [[ -n "$DEVID_ID" ]]; then
    codesign --force --options runtime --timestamp -s "$DEVID_ID" "$1"
  else
    codesign --force -s - "$1"
  fi
}

echo "==> Signing (${DEVID_ID:-ad-hoc})…"
# Sparkle first (inside-out): XPC services, helper apps, the dylib, the framework.
SPK="$APP/Contents/Frameworks/Sparkle.framework/Versions/B"
sign_helper "$SPK/XPCServices/Downloader.xpc"
sign_helper "$SPK/XPCServices/Installer.xpc"
sign_helper "$SPK/Updater.app"
sign_helper "$SPK/Autoupdate"
sign_helper "$SPK/Sparkle"
sign_helper "$APP/Contents/Frameworks/Sparkle.framework"

# Then our code, inside-out: form helper, engine, GUI, then the outer bundle.
sign "$APP/Contents/Helpers/ExpandrForm.app/Contents/MacOS/ExpandrForm"
sign "$APP/Contents/Helpers/ExpandrForm.app"
sign "$AGENT_APP/Contents/MacOS/espanso"
sign "$AGENT_APP"
sign "$APP/Contents/MacOS/ExpandrSnippets"
sign "$APP"

echo "==> Verifying signature…"
codesign --verify --deep --strict --verbose=2 "$APP" 2>&1 | tail -3 || true

echo "built: $APP  (version ${EXPANDR_VERSION}, ${DEVID_ID:-ad-hoc})"
