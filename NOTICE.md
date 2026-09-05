# NOTICE

Expandr is a fork of [espanso](https://github.com/espanso/espanso), a
cross-platform text expander created by Federico Terzi and contributors and
licensed under the GNU General Public License, version 3 (GPL-3.0).

Expandr is maintained by Daniel Fyles and is likewise licensed under the
[GPL-3.0](/LICENSE). It retains all upstream copyright notices. Modifications
made in this fork are Copyright © 2026 Daniel Fyles and are released under the
same GPL-3.0 license.

Expandr is an independent fork and is **not affiliated with, sponsored by, or
endorsed by** the espanso project or its authors. "espanso" is the name of the
upstream project and its authors' mark; this fork is distributed under the name
"Expandr" and does not use the espanso name or logo to identify itself.

## Summary of changes from upstream espanso

Beginning in 2026, this fork adds a native macOS experience on top of espanso's
engine. The most significant changes are:

- **Expandr Snippets** — a native SwiftUI application (`expandr-app/`) for
  browsing and editing snippet files, with multiple snippet sources, per-source
  read-only folders, global search, a visual form designer, and variable
  editing.
- **ExpandrForm** — a native SwiftUI form/choice renderer for macOS (invoked by
  the espanso worker) in place of the previous wxWidgets-based UI.
- **Additional snippet sources** — the ability to read and expand snippets from
  extra folders (for example a shared cloud drive), including warnings for cloud
  folders whose files are not available offline.
- Assorted macOS packaging and branding changes: the application is built and
  distributed as "Expandr" rather than "espanso".

For the complete and authoritative record of what changed and when, see the
project's git commit history.
