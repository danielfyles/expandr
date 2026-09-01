#!/usr/bin/env bash
#
# Create a STABLE self-signed code-signing identity for the Expandr dev build,
# so the macOS Accessibility (TCC) grant survives rebuilds.
#
# Why: ad-hoc signatures (`codesign -s -`) are keyed by content hash, which
# changes every build -> the Accessibility grant is invalidated each rebuild.
# A signature made with a stable identity is keyed by that identity's
# designated requirement instead, so you grant Accessibility ONCE.
#
# This is fully self-contained and needs NOTHING from you:
#   - the identity lives in a DEDICATED keychain with a password set here
#     (NOT your login password); your login keychain is never touched
#   - the cert is only used for LOCAL signing; it is NOT added to any system
#     trust root, so system security is unaffected
#
# Idempotent: re-running detects the existing identity and does nothing.
#
# Usage:  ./scripts/setup-dev-signing.sh
# Then rebuild via ./espanso-dev.sh build (which auto-uses this identity),
# and re-grant Accessibility ONE final time.

set -euo pipefail

IDENTITY_CN="Expandr Dev"
KEYCHAIN_NAME="expandr-dev.keychain"
KEYCHAIN_PATH="$HOME/Library/Keychains/${KEYCHAIN_NAME}-db"
KEYCHAIN_PASS="expandr-dev"          # password for THIS keychain only (not login)
OPENSSL="/opt/homebrew/opt/openssl@3/bin/openssl"
[ -x "$OPENSSL" ] || OPENSSL="$(command -v openssl)"

# Already set up? (identity present in the dedicated keychain)
if [ -f "$KEYCHAIN_PATH" ] && \
   security find-identity -p codesigning "$KEYCHAIN_PATH" 2>/dev/null | grep -q "$IDENTITY_CN"; then
  echo "identity '$IDENTITY_CN' already present in $KEYCHAIN_NAME — nothing to do."
  security find-identity -p codesigning "$KEYCHAIN_PATH" | grep "$IDENTITY_CN"
  exit 0
fi

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

echo "1/5 generating self-signed code-signing certificate ($IDENTITY_CN)..."
"$OPENSSL" req -x509 -newkey rsa:2048 -nodes \
  -keyout "$tmp/key.pem" -out "$tmp/cert.pem" -days 3650 \
  -subj "/CN=${IDENTITY_CN}" \
  -addext "keyUsage=critical,digitalSignature" \
  -addext "extendedKeyUsage=critical,codeSigning" \
  -addext "basicConstraints=critical,CA:false"
# -legacy: use the SHA1-based PKCS#12 MAC/encryption that Apple's `security`
# can import (OpenSSL 3 defaults to a newer scheme macOS rejects). A non-empty
# transient passphrase avoids Apple's empty-password MAC-verification quirk;
# the p12 is deleted right after import.
P12_PASS="transient-import-pass"
"$OPENSSL" pkcs12 -export -legacy -inkey "$tmp/key.pem" -in "$tmp/cert.pem" \
  -out "$tmp/identity.p12" -passout "pass:${P12_PASS}"

echo "2/5 creating dedicated keychain ($KEYCHAIN_NAME)..."
security delete-keychain "$KEYCHAIN_PATH" 2>/dev/null || true
security create-keychain -p "$KEYCHAIN_PASS" "$KEYCHAIN_PATH"
# no auto-lock (timeout) so codesign never gets blocked mid-build
security set-keychain-settings "$KEYCHAIN_PATH"
security unlock-keychain -p "$KEYCHAIN_PASS" "$KEYCHAIN_PATH"

echo "3/5 importing identity and allowing codesign to use it..."
security import "$tmp/identity.p12" -k "$KEYCHAIN_PATH" -P "$P12_PASS" \
  -T /usr/bin/codesign -A
# grant codesign non-interactive access to the private key
security set-key-partition-list -S apple-tool:,apple: -s \
  -k "$KEYCHAIN_PASS" "$KEYCHAIN_PATH" >/dev/null 2>&1 || true

echo "4/5 adding keychain to the user search list (preserving existing)..."
existing="$(security list-keychains -d user | sed -e 's/^[[:space:]]*"//' -e 's/"$//')"
if ! printf '%s\n' "$existing" | grep -qF "$KEYCHAIN_PATH"; then
  # shellcheck disable=SC2086
  security list-keychains -d user -s "$KEYCHAIN_PATH" $existing
fi

echo "5/5 verifying..."
security find-identity -p codesigning "$KEYCHAIN_PATH" | grep "$IDENTITY_CN" \
  || { echo "ERROR: identity not found after setup"; exit 1; }

echo
echo "Done. Sign with:  codesign -s \"$IDENTITY_CN\" --force <binary>"
echo "espanso-dev.sh will use it automatically on the next build."
