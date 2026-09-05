#!/usr/bin/env bash
#
# Build the Expandr Snippets SwiftUI app and bundle it into a Dock .app.
#
# Usage:
#   ./build-app.sh              # build + bundle (+ ad-hoc/dev sign)
#   ./build-app.sh run          # ...then launch it against the dev config
#
# The dev instance's config (~/espanso-dev/config) is used when launched via
# `run`, so edits land in files the dev espanso agent watches.

set -Eeuf -o pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$HERE/.." && pwd)"
APP="$HERE/build/Expandr Snippets.app"
EXE_NAME="ExpandrSnippets"
IDENTITY="Expandr Dev"   # falls back to ad-hoc if not present

swift build -c release --package-path "$HERE"
BIN="$HERE/.build/release/$EXE_NAME"

rm -rf -- "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/$EXE_NAME"
cp "$REPO/espanso/src/res/macos/icon.icns" "$APP/Contents/Resources/icon.icns"

# Bundle the brand fonts (Fraunces headings, Newsreader body); registered at
# launch via CTFontManager from Contents/Resources/Fonts.
mkdir -p "$APP/Contents/Resources/Fonts"
cp "$REPO/espanso-ui/fonts/Fraunces.ttf"  "$APP/Contents/Resources/Fonts/"
cp "$REPO/espanso-ui/fonts/Newsreader.ttf" "$APP/Contents/Resources/Fonts/"

# Optional help image shown in the "folder might be offline" modal (Settings).
# Drop a PNG at expandr-app/Resources/offline-fix.png and it gets bundled.
if [ -f "$HERE/Resources/offline-fix.png" ]; then
  cp "$HERE/Resources/offline-fix.png" "$APP/Contents/Resources/offline-fix.png"
fi

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key>              <string>Expandr Snippets</string>
  <key>CFBundleDisplayName</key>       <string>Expandr Snippets</string>
  <key>CFBundleIdentifier</key>        <string>app.expandr.snippets</string>
  <key>CFBundleExecutable</key>        <string>ExpandrSnippets</string>
  <key>CFBundlePackageType</key>       <string>APPL</string>
  <key>CFBundleShortVersionString</key><string>0.1.0</string>
  <key>CFBundleVersion</key>           <string>0.1.0</string>
  <key>CFBundleIconFile</key>          <string>icon</string>
  <key>NSPrincipalClass</key>          <string>NSApplication</string>
  <key>NSHighResolutionCapable</key>   <true/>
  <key>LSMinimumSystemVersion</key>    <string>13.0</string>
</dict>
</plist>
PLIST

echo "APPL????" > "$APP/Contents/PkgInfo"

if security find-identity -p codesigning 2>/dev/null | grep -q "$IDENTITY"; then
  codesign --force --deep -s "$IDENTITY" "$APP" >/dev/null 2>&1 || codesign --force --deep -s - "$APP"
else
  codesign --force --deep -s - "$APP"
fi
echo "built: $APP"

# Also build the form renderer as a sibling helper (build/ExpandrForm.app) so the
# in-app Form Preview can find it next to this app.
"$HERE/build-form-app.sh" >/dev/null && echo "built form renderer sibling: $HERE/build/ExpandrForm.app"

if [ "${1:-}" = "run" ]; then
  echo "launching against ~/espanso-dev/config ..."
  # Launch the bundled executable directly (not via `open`) so ESPANSO_CONFIG_DIR
  # reaches the app — LaunchServices does not inherit the shell environment.
  ESPANSO_CONFIG_DIR="$HOME/espanso-dev/config" \
    EXPANDR_FORM_BIN="$HERE/build/ExpandrForm.app/Contents/MacOS/ExpandrForm" \
    "$APP/Contents/MacOS/$EXE_NAME" &
  echo "launched (pid $!)"
fi
