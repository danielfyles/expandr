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

use anyhow::{bail, Result};
use serde_json::json;
use std::collections::HashMap;
use std::io::Write;
use std::path::PathBuf;
use std::process::{Command, Stdio};

use crate::gui::modulo::form::ModuloFormUIOptionProvider;
use crate::gui::{
    FormField, FormUI, ModifierStateResetter, SearchItem, SearchUI, SearchUIOptionProvider,
};

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

/// A `FormUI` backed by the native SwiftUI form renderer (`ExpandrForm`). It
/// speaks the same JSON contract espanso already uses for modulo forms — the
/// spec goes in on stdin, the filled values come back on stdout — but points at
/// our own attractive renderer instead of the wxWidgets one.
pub struct NativeFormUI<'a> {
    option_provider: &'a dyn ModuloFormUIOptionProvider,
}

impl<'a> NativeFormUI<'a> {
    pub fn new(option_provider: &'a dyn ModuloFormUIOptionProvider) -> Self {
        Self { option_provider }
    }
}

impl FormUI for NativeFormUI<'_> {
    fn show(
        &self,
        layout: &str,
        fields: &HashMap<String, FormField>,
    ) -> Result<Option<HashMap<String, String>>> {
        let config = json!({
            "title": "espanso",
            "layout": layout,
            "fields": fields_to_json(fields),
            "max_form_width": self.option_provider.get_max_form_width(),
            "max_form_height": self.option_provider.get_max_form_height(),
        });
        let json_config = serde_json::to_string(&config)?;

        let bin = form_renderer_path()?;
        let mut child = Command::new(&bin)
            .stdin(Stdio::piped())
            .stdout(Stdio::piped())
            .spawn()?;

        // Write the spec and close stdin so the renderer's read-to-EOF returns.
        {
            let mut stdin = child
                .stdin
                .take()
                .ok_or_else(|| anyhow::anyhow!("failed to open form renderer stdin"))?;
            stdin.write_all(json_config.as_bytes())?;
        }

        // Blocks this render thread until the user submits/cancels — same as the
        // modulo subprocess did.
        let output = child.wait_with_output()?;
        let stdout = String::from_utf8_lossy(&output.stdout);
        let values: HashMap<String, String> = serde_json::from_str(stdout.trim()).unwrap_or_default();

        let post_form_delay = self.option_provider.get_post_form_delay();
        if post_form_delay > 0 {
            std::thread::sleep(std::time::Duration::from_millis(post_form_delay as u64));
        }

        // An empty result means the user cancelled → no expansion.
        if values.is_empty() {
            Ok(None)
        } else {
            Ok(Some(values))
        }
    }
}

/// Serialize form fields into the same JSON object shape espanso's modulo path
/// emits (so the renderer can be schema-compatible with both).
fn fields_to_json(fields: &HashMap<String, FormField>) -> serde_json::Value {
    let mut obj = serde_json::Map::new();
    for (name, field) in fields {
        let value = match field {
            FormField::Text { default, multiline } => json!({
                "type": "text", "default": default, "multiline": multiline,
            }),
            FormField::Choice { default, values } => json!({
                "type": "choice", "default": default, "values": values,
            }),
            FormField::List {
                default,
                values,
                separator,
            } => json!({
                "type": "list", "default": default, "values": values, "separator": separator,
            }),
        };
        obj.insert(name.clone(), value);
    }
    serde_json::Value::Object(obj)
}

/// Locate the `ExpandrForm` renderer:
/// 1. `$EXPANDR_FORM_BIN` if set (used in dev),
/// 2. the nested helper bundle in the shipping app
///    (`Expandr.app/Contents/Helpers/ExpandrForm.app/Contents/MacOS/ExpandrForm`),
/// 3. a bare sibling of the running executable.
fn form_renderer_path() -> Result<PathBuf> {
    if let Ok(path) = std::env::var("EXPANDR_FORM_BIN") {
        let path = PathBuf::from(path);
        if path.exists() {
            return Ok(path);
        }
    }
    if let Ok(exe) = std::env::current_exe() {
        // exe is Expandr.app/Contents/MacOS/espanso → dir is Contents/MacOS.
        if let Some(dir) = exe.parent() {
            if let Some(contents) = dir.parent() {
                let nested =
                    contents.join("Helpers/ExpandrForm.app/Contents/MacOS/ExpandrForm");
                if nested.exists() {
                    return Ok(nested);
                }
            }
            let sibling = dir.join("ExpandrForm");
            if sibling.exists() {
                return Ok(sibling);
            }
        }
    }
    bail!("could not locate the ExpandrForm renderer (set EXPANDR_FORM_BIN)")
}
