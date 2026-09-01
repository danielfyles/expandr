# Espanso → First-Class Native Mac App — Assessment & Plan

> Working notes on turning espanso into a first-class, reliable macOS app with
> native UI and a proper menu-bar presence. Based on a full read of the codebase
> (tray layer, GUI/window layer, process model, detection/injection, packaging,
> permissions). Not upstream documentation — a strategy note.

## TL;DR

espanso has a genuinely good engine and surprisingly good bones on macOS, but is
not yet a first-class Mac app. The gap is almost entirely in **two areas**:

1. **The GUI windows are wxWidgets** (vendored, compiled-from-source C++).
2. **Distribution is unsigned and manual** (no notarization, no DMG, no self-update).

The menu-bar icon is **already native Cocoa**, so we're closer than it looks. The
work splits cleanly into "polish what's already native" and "replace what isn't."

---

## Baseline: where it stands today

### Already native / solid (keep)
- **Menu bar = real AppKit.** `NSStatusItem` + `NSMenu`, Objective-C++, in
  `espanso-ui/src/mac/AppDelegate.mm`. Template image with light/dark auto-tint,
  JSON-driven context menu built by `addSubMenu`/`addSingleMenu`. Right foundation.
- **Rust core is clean and cross-platform:**
  - Detection: `espanso-detect/src/mac/` — global `NSEvent` monitor (not a
    CGEventTap) + Carbon `RegisterEventHotKey` for hotkeys. Needs Accessibility.
  - Injection: `espanso-inject/src/mac/` — `CGEvent` synthesis to `kCGHIDEventTap`;
    injected events stamped with a sentinel location so the detector ignores them.
  - IPC: `espanso-ipc` — Unix domain sockets, newline-delimited JSON.
- **Process model is sound:** single binary re-exec'ing itself into three roles —
  `launcher → daemon → worker` (`espanso/src/cli/{launcher,daemon,worker}/`).
  launchd LaunchAgent, lock files, config file-watching → worker restart.

### Problems (fix)
1. **Every window is wxWidgets.** Search bar, forms, first-run wizard, welcome,
   troubleshooting, text viewer — all in `espanso-modulo`, built by compiling a
   **vendored wxWidgets 3.1.5 zip from source** in `espanso-modulo/build.rs`. They
   run as a **separate child process** (`espanso modulo <kind>`) over stdin/stdout
   JSON (`espanso/src/gui/modulo/manager.rs`). Biggest blocker to "native." The
   flagship search bar (`espanso-modulo/src/sys/search/search.cpp`) is a borderless
   wxFrame with HTML-rendered rows — and looks like it.
2. **Distribution unsigned & manual.** CI only produces an unsigned zip
   (`ditto … Espanso-Mac-Universal.zip`); **no codesign / notarize / DMG / hardened
   runtime** (`.github/workflows/create-release-draft.yml`; noted in
   `docs/src/ch04-03-creating-a-release.md`). Causes Gatekeeper friction +
   app-translocation bugs that espanso then defends against at runtime.
3. **No self-update.** No Sparkle / update check anywhere. Upgrades are manual.
4. **Aging native details:**
   - Notifications use **deprecated `NSUserNotification`** (`AppDelegate.mm:88`).
   - UI heartbeat is a crude **1-second `NSTimer`**.
   - Login item is a hand-written launchd plist poked with `launchctl`
     (`espanso/src/cli/service/macos.rs`), not modern `SMAppService`.
   - PATH setup shells out to an `osascript` admin prompt.
5. **Menu is minimal.** Icon click just pops the context menu — no rich status,
   no well-surfaced quick toggles, no live state.

### Facts worth remembering
- Config: YAML under `~/Library/Application Support/espanso` (+ legacy/portable
  fallbacks). Runtime dir `~/Library/Caches/espanso`. Auto-reloaded.
- Permissions: only **Accessibility** is checked/prompted
  (`espanso-mac-utils/src/native.mm`, `espanso/src/cli/launcher/accessibility.rs`).
  Input Monitoring not handled — verify whether current macOS needs it too.
- Bundle: `LSUIElement=1` (agent app, no Dock icon), `LSRequiresCarbon=true`.
  `MAC_LAUNCH_CONTEXT=bundle` env → double-click runs the `launcher` subcommand.
- Existing Obj-C++ glue we can build on: `espanso-ui/src/mac/*.mm`,
  `espanso-modulo/src/sys/common/mac.mm`, `espanso-mac-utils/src/native.mm`.

---

## The strategic fork (decide this first)

**Path A — Native UI *inside* the Rust binary (incremental).**
Keep single-binary, cross-platform structure. Replace wxWidgets `modulo` windows
with native AppKit/SwiftUI compiled into the binary — the way `espanso-ui` already
embeds Obj-C++ for the tray. Each window is an isolated `espanso modulo <kind>`
subprocess over a JSON contract (`espanso-modulo/src/sys/interop/interop.h`), so we
can swap the renderer **window-by-window** without touching Rust callers. Lowest
risk, stays upstream-mergeable.

**Path B — Swift/SwiftUI host app driving the Rust engine (clean shell).**
Build `Espanso.app` as a real Swift app owning menu bar, windows, onboarding,
Settings, Sparkle — running the existing Rust `worker`/`daemon` as its engine over
the existing IPC socket. Best possible Mac app; unlocks SwiftUI / `SMAppService` /
`UNUserNotificationCenter` idiomatically. Cost: hard fork from the cross-platform
model, larger up-front build.

**Recommendation:** Start on **A**, let it converge toward **B**. Reimplement the
menu bar and search bar natively first (highest visibility, lowest coupling), prove
out a Swift↔Rust bridge, and only commit to a full Swift host if the direction is
"macOS-first, best-in-class." Nothing in A is wasted if we later go to B.

---

## Prioritized workstreams

**1. Menu bar presence (native, build on what's there) — highest ROI, lowest risk.**
- Rich dropdown: enable/disable toggle with live checkmark, "Search…", "Open Config
  Folder", "Preferences…", "Reload", status line (Active / Disabled / ⚠︎ Accessibility
  off), recent expansions, packages.
- **SF Symbols** template icon with active/paused/error states (vs PNG swaps).
- Optional `NSPopover` panel (AppKit or embedded SwiftUI) for modern quick-status.
- Replace the 1s `NSTimer` heartbeat with an event-driven health signal.

**2. Native search bar (flagship).** Most-seen, most obviously non-native. Native
SwiftUI/AppKit replacement speaking the same `espanso modulo search` JSON contract
so Rust is unchanged. Fuzzy match, dark mode, vibrancy, ⌘-styling.

**3. Replace remaining windows** (forms → wizard → troubleshooting → welcome →
textview), then **delete the vendored wxWidgets build** — also removes a large,
slow, fragile part of the build.

**4. Reliability & distribution (parallel — independent of UI).**
- Automate **codesign + notarize + staple + hardened runtime + entitlements** in CI;
  ship a **DMG** with drag-to-Applications. Kills translocation bugs at the source.
- Add **Sparkle** auto-update.
- Modern **`UNUserNotificationCenter`** notifications; **`SMAppService`** login item.

**5. Permissions onboarding polish.** Verify Input Monitoring requirement; native
guided pane with deep-links to the right System Settings panes + live status polling.

---

## Suggested first moves (lowest risk, highest signal)
1. Native menu-bar upgrade in `espanso-ui/src/mac` (richer `NSMenu` + SF Symbols +
   optional popover). Small, self-contained, immediately visible.
2. CI signing/notarization/DMG pipeline. Pure infra, no code risk, fixes the worst
   reliability complaint.
3. Native search bar as the first `modulo` replacement — proves the Swift↔Rust
   bridge pattern for the rest.

Items 1 and 2 alone move espanso a long way toward "first-class and reliable"
without boiling the ocean.

---

## Running a dev build side-by-side with the installed app

The official espanso and a dev build **can coexist installed and runnable**, as long
as the dev instance's data dirs are isolated and it is run **unmanaged** (never
registers its launchd service). Everything runtime-related is keyed off three
overridable directories.

**Collision points and fixes:**

| Collision | Where it lives | Fix |
|---|---|---|
| Lock files (`espanso-daemon.lock`, `espanso-worker.lock`) | `runtime_dir` (`espanso/src/lock.rs:39`) | `--runtime_dir` |
| IPC sockets (`*.sock`) | `runtime_dir` (`espanso-ipc/src/unix.rs:38`) | `--runtime_dir` |
| Config + matches | `~/Library/Application Support/espanso` | `--config_dir` |
| Packages | `<config>/match/packages` | `--package_dir` |
| launchd LaunchAgent — label `com.federicoterzi.espanso`, hardcoded (`espanso/src/cli/service/macos.rs:32`) | `~/Library/LaunchAgents/` | **Don't register the dev build as a service** — run unmanaged |
| `/usr/local/bin/espanso` symlink | PATH | Don't run `env-path register` on the dev build |
| Accessibility grant | keyed to binary identity | Dev binary gets its own entry — grant it separately |

Overrides also accept env vars: `ESPANSO_CONFIG_DIR`, `ESPANSO_RUNTIME_DIR`,
`ESPANSO_PACKAGE_DIR` (`espanso/src/main.rs:587`).

**Behavioral caveat:** both instances install a global keyboard monitor and both
inject text. If both are *actively expanding at the same instant*, a trigger fires
in both → doubled/garbled output. They can both be installed and running, but keep
only **one actively expanding at a time** — click Disable in the original's menu bar
(or quit it) while testing the dev build, then re-enable.

**Recipe:** use the `./espanso-dev.sh` helper in the repo root
(`build` / `start` / `stop` / `restart` / `log` / `status`). It encapsulates the
working approach below. Verified working: dev instance runs side-by-side with the
installed `/Applications/Espanso.app` with zero collision (separate sockets under
`~/espanso-dev/runtime`).

Key gotchas learned in practice:
- **Pass the dir overrides as env vars** (`ESPANSO_CONFIG_DIR` / `ESPANSO_RUNTIME_DIR`
  / `ESPANSO_PACKAGE_DIR`), *not* the `--config_dir` flags — the flags collide with
  the `start` alias preprocessing (`InvalidSubcommand`).
- **Run `espanso daemon` directly, not `service start --unmanaged`.** The unmanaged
  path forks and re-execs `espanso launcher`, and in a **no-`modulo`** build the
  launcher is `unimplemented!()` (`espanso/src/cli/launcher/mod.rs:205`) → "launcher
  spawn failure". Running `daemon` directly spawns the worker and the tray fine.
- **Seed the config dir first** (`config/default.yml` + `match/base.yml` from
  `espanso/src/res/config/`) — normally the launcher does this; without it, config
  load panics with "missing config directory".

```bash
# 1. Fast build (no modulo → skips the vendored wxWidgets compile)
cargo build --release --no-default-features --features native-tls
codesign -s - --force ./target/release/espanso

# 2. Seed isolated config + run the daemon directly
export ESPANSO_CONFIG_DIR=~/espanso-dev/config \
       ESPANSO_RUNTIME_DIR=~/espanso-dev/runtime \
       ESPANSO_PACKAGE_DIR=~/espanso-dev/packages MAC_LAUNCH_CONTEXT=cli
# (copy default.yml + base.yml into $ESPANSO_CONFIG_DIR first — see espanso-dev.sh)
./target/release/espanso daemon &

# Stop: pkill -f 'target/release/espanso'
```

**Two tips that save real pain:**
- **Ad-hoc sign the dev binary** so its Accessibility grant survives rebuilds:
  `codesign -s - --force ./target/release/espanso`. Unsigned binaries lose AX trust
  on every rebuild, forcing a re-grant each time.
- **For menu-bar work, drop the `modulo` feature** (`--features native-tls` only).
  The tray/menu-bar code in `espanso-ui` is *not* behind the `modulo` flag, but the
  wxWidgets windows are — so a no-`modulo` build skips the slow vendored wxWidgets
  compile and iterates much faster. You lose the search/wizard windows, which you
  don't need while iterating on the menu bar.

**Optional, for full cleanliness:** for a `.app` bundle, bump its
`CFBundleIdentifier` to `com.federicoterzi.espanso.dev` in a dev copy of
`espanso/src/res/macos/Info.plist` — a fully distinct identity for permissions and
notifications, at the cost of one fresh Accessibility grant.

---

## Licensing & distribution constraints

> Not legal advice — confirm with an IP lawyer before shipping anything public.

**License:** espanso is **GPL-3.0-or-later** (`LICENSE`; per-file headers say
"either version 3 … or (at your option) any later version"). Copyright is held by
**Federico Terzi plus many contributors**, and there is **no CLA / copyright
assignment** anywhere in the repo — so the copyright is collectively owned and no
single person holds all the rights.

### App Store is not a realistic target — blocked on two independent grounds

**1. GPL vs App Store terms (licensing).** Any "improved espanso" is a derivative
work and must stay GPLv3. Apple's App Store terms add restrictions GPLv3 forbids:
- §10 "no further restrictions" vs Apple's per-Apple-ID device usage rules;
- GPLv3 §3 anti-DRM vs Apple's FairPlay DRM wrapping.

This is why **VLC (GPLv2) was pulled from the App Store in 2011** after one copyright
holder complained. GPLv3 is considered *more* incompatible. The usual escape hatch —
"the copyright holder isn't bound by their own license" — **does not apply here**,
because with many contributors and no CLA you can't unilaterally authorize it; you'd
need permission from every copyright holder. Note: **"free" is irrelevant** — GPL
restricts what you can do, not what you charge.

**2. The sandbox forbids the functionality (technical, license-independent).** Mac
App Store apps must be sandboxed, and the sandbox does **not** permit system-wide
keystroke monitoring or system-wide text injection — which is espanso's entire core
(global `NSEvent` monitor in `espanso-detect`, `CGEvent` injection in
`espanso-inject`, the Accessibility API). Even a clean-room, sole-authored rewrite
would very likely **fail Mac App Store review** on these grounds. (This is why every
serious Mac text expander — TextExpander, aText, Typinator, Alfred — ships *outside*
the Mac App Store as a notarized direct download.)

### Viable routes

| Route | Viable? |
|---|---|
| Improved espanso → Mac App Store (free or paid) | ❌ Blocked twice: GPL conflict *and* sandbox forbids the functionality |
| Improved espanso → **notarized DMG / Homebrew cask** | ✅ Fully fine — GPLv3 is happy here |
| Clean-room rewrite (your own code) → App Store | ⚠️ License-clean, but still hits the sandbox wall for a text expander |

**Bottom line:** target a **signed, notarized DMG + Homebrew cask** (workstream 4).
That delivers first-class distribution and Sparkle auto-update with none of the
conflicts — the App Store buys nothing here and is blocked anyway.

**Trademark:** the "espanso" name is the project's brand — GPL §7(e) lets them
reserve trademark rights and Apple's naming rules apply too — so any public fork
should ship under a **distinct name**.

---

## Progress log

### 2026-09-01 — Dev loop established + Workstream 1 (menu bar) first pass ✅

**Dev loop working** (verified side-by-side with official `/Applications/Espanso.app`):
`./espanso-dev.sh {build|start|stop|restart|log|status}`. Fast no-`modulo` build,
isolated `~/espanso-dev` dirs, run `daemon` directly, ad-hoc signed.

**Menu bar — all three landed and visually confirmed on the dev build:**
1. **SF Symbols tray icon**, state-varying + theme-aware, replacing the PNG swaps:
   Normal → `keyboard`, Disabled → `pause.circle`, SystemDisabled →
   `exclamationmark.triangle`. Falls back to the bundled PNGs pre-macOS 11.
2. **Status header** — a greyed, non-clickable top line: "espanso: active" /
   "espanso: disabled" / secure-input variant.
3. **Native checkmark toggle** — single "Enabled" item with `NSMenuItem` checkmark,
   replacing the label-swap Enable/Disable.

Files touched:
- `espanso-engine/src/event/ui.rs` — added `checked` + `enabled` to `SimpleMenuItem` (+ `::new`).
- `espanso-engine/src/process/middleware/context_menu.rs` — status header, checkmark
  toggle, `CONTEXT_ITEM_STATUS_HEADER`, defensive click catch-all.
- `espanso-ui/src/menu.rs` — mirrored fields (serde defaults) + updated test.
- `espanso/src/cli/worker/engine/dispatch/executor/context_menu.rs` — pass fields through.
- `espanso-ui/src/mac/AppDelegate.mm` — checkmark/disabled rendering + SF Symbols icon.

Cross-platform: Windows/Linux menu JSON parsers ignore the new `checked`/`enabled`
fields (graceful degradation; not yet tested on those platforms).

**Not yet done:** Accessibility grant for the dev binary (only needed to test real
expansion); commit to a branch. Deprecated `NSUserNotificationCenter` still in use
(compiler warns) — modernization is a later workstream item.

