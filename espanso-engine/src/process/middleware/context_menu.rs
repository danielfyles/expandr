/*
 * This file is part of espanso.
 *
 * Copyright  id: (), label: () id: (), label: () id: (), label: ()(C) 2019-2021 Federico Terzi
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

use std::cell::RefCell;

use super::super::Middleware;
use crate::event::{
    ui::{MenuItem, ShowContextMenuEvent, SimpleMenuItem},
    Event, EventType, ExitMode,
};

const CONTEXT_ITEM_EXIT: u32 = 0;
const CONTEXT_ITEM_ENABLE: u32 = 2;
const CONTEXT_ITEM_DISABLE: u32 = 3;
const CONTEXT_ITEM_SECURE_INPUT_EXPLAIN: u32 = 4;
const CONTEXT_ITEM_SECURE_INPUT_TRIGGER_WORKAROUND: u32 = 5;
const CONTEXT_ITEM_OPEN_SEARCH: u32 = 6;
const CONTEXT_ITEM_OPEN_EDITOR: u32 = 7;
// Non-actionable status header shown at the top of the tray menu.
const CONTEXT_ITEM_STATUS_HEADER: u32 = 9;

/// LaunchServices bundle id of the outer Expandr.app (the editor GUI). The engine
/// runs from a nested sub-app, so it drives the editor by bundle id rather than
/// by path.
#[cfg(target_os = "macos")]
const EDITOR_BUNDLE_ID: &str = "app.expandr";
/// Process name of the editor GUI executable (used to quit it on Exit).
#[cfg(target_os = "macos")]
const EDITOR_PROCESS_NAME: &str = "ExpandrSnippets";

/// Launch or activate the editor GUI (the outer Expandr.app). Fire-and-forget:
/// spawns `open -b <bundle id>` and doesn't wait.
#[cfg(target_os = "macos")]
fn launch_editor() {
    let _ = std::process::Command::new("/usr/bin/open")
        .args(["-b", EDITOR_BUNDLE_ID])
        .spawn();
}
#[cfg(not(target_os = "macos"))]
fn launch_editor() {}

/// Ask the editor GUI to quit (a graceful SIGTERM; the editor autosaves). Called
/// as part of "Exit Expandr" so the whole product goes down together.
#[cfg(target_os = "macos")]
fn quit_editor() {
    let _ = std::process::Command::new("/usr/bin/pkill")
        .args(["-x", EDITOR_PROCESS_NAME])
        .spawn();
}
#[cfg(not(target_os = "macos"))]
fn quit_editor() {}

pub struct ContextMenuMiddleware {
    is_enabled: RefCell<bool>,
    is_secure_input_enabled: RefCell<bool>,
    // The menu is attached to the tray item natively, so push it once at startup.
    menu_initialized: RefCell<bool>,
}

impl ContextMenuMiddleware {
    pub fn new() -> Self {
        Self {
            is_enabled: RefCell::new(true),
            is_secure_input_enabled: RefCell::new(false),
            menu_initialized: RefCell::new(false),
        }
    }

    // Build the tray menu reflecting the current enabled / secure-input state.
    fn build_menu_event(&self, source_id: u32) -> Event {
        let is_enabled = *self.is_enabled.borrow();
        let is_secure_input_enabled = *self.is_secure_input_enabled.borrow();

        // Non-actionable header line reflecting espanso's current status.
        let status_label = if is_secure_input_enabled {
            "Expandr: secure input is blocking expansions"
        } else if is_enabled {
            "Expandr: active"
        } else {
            "Expandr: disabled"
        };
        let status_header = MenuItem::Simple(SimpleMenuItem {
            id: CONTEXT_ITEM_STATUS_HEADER,
            label: status_label.to_string(),
            checked: false,
            enabled: false,
        });

        // Single toggle carrying a native checkmark instead of swapping the label.
        let toggle_enabled = MenuItem::Simple(SimpleMenuItem {
            id: if is_enabled {
                CONTEXT_ITEM_DISABLE
            } else {
                CONTEXT_ITEM_ENABLE
            },
            label: "Enabled".to_string(),
            checked: is_enabled,
            enabled: true,
        });

        let mut items = vec![
            status_header,
            MenuItem::Separator,
            toggle_enabled,
            MenuItem::Simple(SimpleMenuItem::new(
                CONTEXT_ITEM_OPEN_EDITOR,
                "Open snippet editor",
            )),
            MenuItem::Simple(SimpleMenuItem::new(CONTEXT_ITEM_OPEN_SEARCH, "Open search bar")),
            MenuItem::Separator,
            MenuItem::Simple(SimpleMenuItem::new(CONTEXT_ITEM_EXIT, "Exit Expandr")),
        ];

        if is_secure_input_enabled {
            // Surface the secure-input remedies right below the header.
            items.insert(
                2,
                MenuItem::Simple(SimpleMenuItem::new(
                    CONTEXT_ITEM_SECURE_INPUT_EXPLAIN,
                    "Why is Expandr not working?",
                )),
            );
            items.insert(
                3,
                MenuItem::Simple(SimpleMenuItem::new(
                    CONTEXT_ITEM_SECURE_INPUT_TRIGGER_WORKAROUND,
                    "Launch SecureInput auto-fix",
                )),
            );
            items.insert(4, MenuItem::Separator);
        }

        Event::caused_by(
            source_id,
            EventType::ShowContextMenu(ShowContextMenuEvent { items }),
        )
    }
}

impl Middleware for ContextMenuMiddleware {
    fn name(&self) -> &'static str {
        "context_menu"
    }

    fn next(&self, event: Event, dispatch: &mut dyn FnMut(Event)) -> Event {
        // Attach the menu to the tray item once, shortly after startup.
        if !*self.menu_initialized.borrow() {
            *self.menu_initialized.borrow_mut() = true;
            dispatch(self.build_menu_event(event.source_id));
        }

        match &event.etype {
            // The menu is attached natively, so a click opens it directly; this
            // path only runs as a fallback if the menu hasn't been pushed yet.
            EventType::TrayIconClicked => self.build_menu_event(event.source_id),
            EventType::ContextMenuClicked(context_click_event) => {
                match context_click_event.context_item_id {
                    CONTEXT_ITEM_EXIT => {
                        // "Exit Expandr" tears the whole product down: quit the
                        // editor GUI, then exit the engine's own processes.
                        quit_editor();
                        Event::caused_by(
                            event.source_id,
                            EventType::ExitRequested(ExitMode::ExitAllProcesses),
                        )
                    }
                    CONTEXT_ITEM_OPEN_EDITOR => {
                        launch_editor();
                        Event::caused_by(event.source_id, EventType::NOOP)
                    }
                    CONTEXT_ITEM_ENABLE => {
                        dispatch(Event::caused_by(event.source_id, EventType::EnableRequest));
                        Event::caused_by(event.source_id, EventType::NOOP)
                    }
                    CONTEXT_ITEM_DISABLE => {
                        dispatch(Event::caused_by(event.source_id, EventType::DisableRequest));
                        Event::caused_by(event.source_id, EventType::NOOP)
                    }
                    CONTEXT_ITEM_SECURE_INPUT_EXPLAIN => {
                        dispatch(Event::caused_by(
                            event.source_id,
                            EventType::DisplaySecureInputTroubleshoot,
                        ));
                        Event::caused_by(event.source_id, EventType::NOOP)
                    }
                    CONTEXT_ITEM_SECURE_INPUT_TRIGGER_WORKAROUND => {
                        dispatch(Event::caused_by(
                            event.source_id,
                            EventType::LaunchSecureInputAutoFix,
                        ));
                        Event::caused_by(event.source_id, EventType::NOOP)
                    }
                    CONTEXT_ITEM_OPEN_SEARCH => {
                        dispatch(Event::caused_by(event.source_id, EventType::ShowSearchBar));
                        Event::caused_by(event.source_id, EventType::NOOP)
                    }
                    // The status header is non-actionable (disabled on macOS); on
                    // platforms that still deliver its click, treat it as a no-op.
                    CONTEXT_ITEM_STATUS_HEADER => {
                        Event::caused_by(event.source_id, EventType::NOOP)
                    }
                    _ => Event::caused_by(event.source_id, EventType::NOOP),
                }
            }
            EventType::Disabled => {
                *self.is_enabled.borrow_mut() = false;
                dispatch(self.build_menu_event(event.source_id));
                event
            }
            EventType::Enabled => {
                *self.is_enabled.borrow_mut() = true;
                dispatch(self.build_menu_event(event.source_id));
                event
            }
            EventType::SecureInputEnabled(_) => {
                *self.is_secure_input_enabled.borrow_mut() = true;
                dispatch(self.build_menu_event(event.source_id));
                event
            }
            EventType::SecureInputDisabled => {
                *self.is_secure_input_enabled.borrow_mut() = false;
                dispatch(self.build_menu_event(event.source_id));
                event
            }
            _ => event,
        }
    }
}
