/*
 * This file is part of espanso.
 *
 * Copyright (C) 2019-2021 Federico Terzi
 *
 * espanso is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * espanso is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with espanso.  If not, see <https://www.gnu.org/licenses/>.
 */

use std::sync::Arc;

use espanso_config::config::Backend;

use crate::patch::patches::{PatchedConfig, Patches};
use crate::patch::PatchDefinition;

// Google Docs, Sheets and Slides run their own editor in JavaScript and only
// keep the first character of the multi-character key events the macOS
// injector posts, so the rest of the snippet is lost. Pasting from the
// clipboard is handled fine, so switch the backend for those pages. Browsers
// set the window title from the page title, which ends in "- Google Docs".
pub fn patch() -> PatchDefinition {
    PatchDefinition {
        name: module_path!().split(':').next_back().unwrap_or("unknown"),
        is_enabled: || cfg!(target_os = "macos"),
        should_patch: |app| is_google_editor_title(app.title.unwrap_or_default()),
        apply: |base, name| {
            Arc::new(PatchedConfig::patch(
                base,
                name,
                Patches {
                    backend: Some(Backend::Clipboard),
                    ..Default::default()
                },
            ))
        },
    }
}

fn is_google_editor_title(title: &str) -> bool {
    ["Google Docs", "Google Sheets", "Google Slides"]
        .iter()
        .any(|suffix| title.contains(suffix))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn matches_google_editor_titles() {
        assert!(is_google_editor_title("Untitled document - Google Docs"));
        assert!(is_google_editor_title("Budget - Google Sheets"));
        assert!(is_google_editor_title("Pitch - Google Slides"));
        assert!(!is_google_editor_title("Inbox - Gmail"));
        assert!(!is_google_editor_title(""));
    }
}
