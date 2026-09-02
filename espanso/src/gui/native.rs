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

//! Native macOS UI implementations that replace the wxWidgets (modulo) windows.

use anyhow::Result;

use crate::gui::{ModifierStateResetter, SearchItem, SearchUI, SearchUIOptionProvider};

/// A `SearchUI` backed by the in-process native AppKit search panel
/// (`espanso-ui`), replacing the wxWidgets/modulo search window on macOS.
pub struct NativeSearchUI<'a> {
    option_provider: &'a dyn SearchUIOptionProvider,
    modifier_resetter: &'a dyn ModifierStateResetter,
}

impl<'a> NativeSearchUI<'a> {
    pub fn new(
        option_provider: &'a dyn SearchUIOptionProvider,
        modifier_resetter: &'a dyn ModifierStateResetter,
    ) -> Self {
        Self {
            option_provider,
            modifier_resetter,
        }
    }
}

impl SearchUI for NativeSearchUI<'_> {
    fn show(&self, items: &[SearchItem], hint: Option<&str>) -> Result<Option<String>> {
        let native_items: Vec<espanso_ui::NativeSearchItem> = items
            .iter()
            .map(|item| espanso_ui::NativeSearchItem {
                label: item.label.clone(),
                trigger: item.tag.clone(),
                terms: item.additional_search_terms.clone(),
            })
            .collect();

        // Runs modally on the main thread and blocks until the user chooses.
        let selected_index = espanso_ui::show_search(hint, &native_items);
        let result = selected_index.map(|index| items[index].id.clone());

        // The modal panel held keyboard focus, so espanso's global monitor
        // missed the release of the modifier that opened it (e.g. ALT from the
        // search hotkey). Clear the stale state so the injector doesn't wait
        // ~3s for a modifier that's already up.
        self.modifier_resetter.clear_modifier_state();

        // Preserve the post-search delay used before injecting into the app that
        // regains focus (see the modulo implementation / config `post_search_delay`).
        let post_search_delay = self.option_provider.get_post_search_delay();
        if post_search_delay > 0 {
            std::thread::sleep(std::time::Duration::from_millis(post_search_delay as u64));
        }

        Ok(result)
    }
}
