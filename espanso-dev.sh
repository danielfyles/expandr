#!/usr/bin/env bash
#
# Dev helper for running an espanso dev build SIDE-BY-SIDE with the installed
# official Espanso.app, without any collision.
#
# Isolation strategy (see NATIVE_MAC_APP_PLAN.md):
#   - separate config/runtime/package dirs under ~/espanso-dev
#   - run the `daemon` directly (the no-modulo build's `launcher` is unimplemented,
#     and `service start --unmanaged` shells out to that launcher)
#   - never register a launchd service, never touch /usr/local/bin
#   - ad-hoc sign the binary so its Accessibility grant survives rebuilds
#
# Usage:  ./espanso-dev.sh {build|start|stop|restart|log|status}
#
# NOTE: only ONE espanso instance should be actively expanding at a time.
#       Disable the official one (its menu bar → Disable) while testing this build.

set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BIN="$REPO/target/release/espanso"
CARGO_BIN="$HOME/.rustup/toolchains/stable-aarch64-apple-darwin/bin/cargo"

export ESPANSO_CONFIG_DIR="$HOME/espanso-dev/config"
export ESPANSO_RUNTIME_DIR="$HOME/espanso-dev/runtime"
export ESPANSO_PACKAGE_DIR="$HOME/espanso-dev/packages"
export MAC_LAUNCH_CONTEXT=cli
# Native SwiftUI form renderer used by NativeFormUI (the daemon passes this env
# to its worker child, which spawns the renderer when a form match fires).
export EXPANDR_FORM_BIN="$REPO/expandr-app/.build/release/ExpandrForm"

seed_config() {
  mkdir -p "$ESPANSO_CONFIG_DIR/config" "$ESPANSO_CONFIG_DIR/match" \
           "$ESPANSO_RUNTIME_DIR" "$ESPANSO_PACKAGE_DIR"
  [ -f "$ESPANSO_CONFIG_DIR/config/default.yml" ] || \
    cp "$REPO/espanso/src/res/config/default.yml" "$ESPANSO_CONFIG_DIR/config/default.yml"
  if [ ! -f "$ESPANSO_CONFIG_DIR/match/base.yml" ]; then
    cp "$REPO/espanso/src/res/config/base.yml" "$ESPANSO_CONFIG_DIR/match/base.yml"
    cat >> "$ESPANSO_CONFIG_DIR/match/base.yml" <<'YAML'

  - trigger: ":devtest"
    replace: "DEV-BUILD-OK"
YAML
  fi
}

case "${1:-}" in
  build)
    # Fast build: no modulo (skips the vendored wxWidgets compile). Add
    # `--features modulo,native-tls` (and `brew install automake`) for the GUI windows.
    "$CARGO_BIN" build --release --no-default-features --features native-tls
    # Sign with the stable "Expandr Dev" identity if present (see
    # scripts/setup-dev-signing.sh) so the Accessibility grant survives rebuilds;
    # otherwise fall back to ad-hoc (grant will need re-granting each build).
    if security find-identity -p codesigning 2>/dev/null | grep -q "Expandr Dev"; then
      codesign -s "Expandr Dev" --force --identifier app.expandr.dev "$BIN"
      echo "built + signed with stable identity 'Expandr Dev': $BIN"
    else
      codesign -s - --force "$BIN"
      echo "built + ad-hoc signed (run scripts/setup-dev-signing.sh for a stable grant): $BIN"
    fi
    # The worker only extracts embedded icons if they're absent (extract_icon
    # skips existing files), so clear the cached ones to pick up icon changes.
    rm -f "$ESPANSO_RUNTIME_DIR"/*v2.png 2>/dev/null || true
    echo "cleared extracted icon cache in runtime dir"
    # Build the native SwiftUI form renderer.
    ( cd "$REPO/expandr-app" && swift build -c release --product ExpandrForm >/dev/null ) \
      && echo "built form renderer: $EXPANDR_FORM_BIN"
    ;;
  start)
    seed_config
    rm -f "$ESPANSO_RUNTIME_DIR"/*.lock 2>/dev/null || true
    echo "starting dev daemon (isolated dirs under ~/espanso-dev)..."
    nohup "$BIN" daemon >/dev/null 2>&1 &
    echo "started (pid $!). Logs: ./espanso-dev.sh log"
    ;;
  stop)
    pkill -f "$BIN worker" 2>/dev/null || true
    pkill -f "$BIN daemon" 2>/dev/null || true
    rm -f "$ESPANSO_RUNTIME_DIR"/*.lock 2>/dev/null || true
    echo "stopped dev instance."
    ;;
  restart)
    "$0" stop; "$0" start
    ;;
  log)
    tail -n "${2:-40}" -f "$ESPANSO_RUNTIME_DIR/espanso.log"
    ;;
  status)
    pgrep -fl "$BIN" || echo "dev instance not running"
    ;;
  *)
    echo "usage: $0 {build|start|stop|restart|log|status}"; exit 1
    ;;
esac
