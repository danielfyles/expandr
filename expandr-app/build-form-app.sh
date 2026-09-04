#!/usr/bin/env bash
#
# Package the ExpandrForm renderer as a minimal LSUIElement .app bundle, so it
# can take keyboard focus for the form while showing NO Dock icon. espanso
# spawns the inner binary directly (piping the form spec via stdin/stdout), and
# macOS still honours the bundle's Info.plist (LSUIElement) — giving us a
# focus-capable agent with no Dock presence.
#
# Usage: ./build-form-app.sh

set -Eeuf -o pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP="$HERE/build/ExpandrForm.app"
EXE_NAME="ExpandrForm"
IDENTITY="Expandr Dev"   # falls back to ad-hoc if not present

swift build -c release --product "$EXE_NAME" --package-path "$HERE"
BIN="$HERE/.build/release/$EXE_NAME"
# SwiftPM emits the bundled fonts as a sidecar resource bundle next to the binary.
RES_BUNDLE="$HERE/.build/release/ExpandrSnippets_${EXE_NAME}.bundle"

rm -rf -- "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/$EXE_NAME"
# Place the resource bundle where Bundle.module can find it (Contents/Resources).
[ -d "$RES_BUNDLE" ] && cp -R "$RES_BUNDLE" "$APP/Contents/Resources/"

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key>              <string>Expandr Form</string>
  <key>CFBundleIdentifier</key>        <string>app.expandr.form</string>
  <key>CFBundleExecutable</key>        <string>ExpandrForm</string>
  <key>CFBundlePackageType</key>       <string>APPL</string>
  <key>CFBundleShortVersionString</key><string>0.1.0</string>
  <key>CFBundleVersion</key>           <string>0.1.0</string>
  <key>NSPrincipalClass</key>          <string>NSApplication</string>
  <key>NSHighResolutionCapable</key>   <true/>
  <key>LSMinimumSystemVersion</key>    <string>13.0</string>
  <key>LSUIElement</key>               <true/>
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
