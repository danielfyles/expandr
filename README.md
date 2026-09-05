# Expandr

> *A native macOS text expander and snippet builder.*

Expandr lets you type a short **trigger** (say `:addr`) and have it instantly
replaced with **something longer** — an address, a canned reply, a code snippet,
today's date, the output of a script — anywhere you can type on your Mac.

It pairs a fast, local expansion engine with **Expandr Snippets**, a native
SwiftUI app for building and organising your snippets, so you don't have to hand‑edit
configuration files (though you still can — everything is plain YAML).

Expandr is a macOS‑focused fork of [espanso](https://github.com/espanso/espanso);
see [Credits & license](#credits--license).

## Features

- **System‑wide expansion** — works in almost any app, 100% locally, with no tracking.
- **Expandr Snippets** — a native app to create and organise snippets: folders,
  global search, drag‑and‑drop, multi‑select, and in‑place editing.
- **Dynamic replacements** — variables for dates, shell output, the clipboard,
  random values and choices, plus a visual **Form designer** with a native
  SwiftUI form/choice renderer.
- **Multiple sources** — read and expand snippets from additional folders
  (e.g. a shared cloud drive), mark any source **read‑only**, and get a warning
  when a cloud folder isn't available offline.
- **Plain‑YAML config** — snippets are simple, portable text files.
- **Regex triggers** and **app‑specific** behaviour, inherited from the engine.

## A snippet looks like this

Snippets are grouped into YAML files. You rarely need to write these by hand —
Expandr Snippets does it for you — but the format is simple:

```yaml
matches:
  - trigger: ":hello"
    replace: "Hi there!"
  - triggers: [":test1", ":test2"]
    replace: "Both of these expand to the same thing"
```

## Building

Requires a recent macOS with Xcode command‑line tools, Swift, and the Rust
toolchain (for the underlying engine).

```bash
# Build and launch the Expandr Snippets app
cd expandr-app
./build-app.sh run
```

The text‑expansion engine is written in Rust (inherited from espanso) and builds
with `cargo`.

## Status

Expandr is an actively developed, macOS‑first project. Expect rough edges.

## Credits & license

Expandr is built on **[espanso](https://github.com/espanso/espanso)**, the
cross‑platform text expander created by [Federico Terzi](http://federicoterzi.com)
and its contributors — huge thanks to them for the engine that makes this possible.

Expandr is an **independent fork**, maintained by Daniel Fyles, and is **not
affiliated with or endorsed by** the espanso project. It does not use the espanso
name or logo to identify itself.

Like espanso, Expandr is licensed under the **[GPL‑3.0](/LICENSE)**. It retains
espanso's copyright notices; modifications in this fork are Copyright © 2026
Daniel Fyles and are released under the same licence. A summary of changes from
upstream is in **[NOTICE.md](/NOTICE.md)**.
