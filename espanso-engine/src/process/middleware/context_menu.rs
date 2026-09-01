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
const CONTEXT_ITEM_RELOAD: u32 = 1;
const CONTEXT_ITEM_ENABLE: u32 = 2;
const CONTEXT_ITEM_DISABLE: u32 = 3;
const CONTEXT_ITEM_SECURE_INPUT_EXPLAIN: u32 = 4;
const CONTEXT_ITEM_SECURE_INPUT_TRIGGER_WORKAROUND: u32 = 5;
const CONTEXT_ITEM_OPEN_SEARCH: u32 = 6;
const CONTEXT_ITEM_SHOW_LOGS: u32 = 7;
const CONTEXT_ITEM_OPEN_CONFIG_FOLDER: u32 = 8;
// Non-actionable status header shown at the top of the tray menu.
const CONTEXT_ITEM_STATUS_HEADER: u32 = 9;

pub struct ContextMenuMiddleware {
    is_enabled: RefCell<bool>,
    is_secure_input_enabled: RefCell<bool>,
}

impl ContextMenuMiddleware {
    pub fn new() -> Self {
        Self {
            is_enabled: RefCell::new(true),
            is_secure_input_enabled: RefCell::new(false),
        }
    }
}

impl Middleware for ContextMenuMiddleware {
    fn name(&self) -> &'static str {
        "context_menu"
    }

    fn next(&self, event: Event, dispatch: &mut dyn FnMut(Event)) -> Event {
        let mut is_enabled = self.is_enabled.borrow_mut();
        let mut is_secure_input_enabled = self.is_secure_input_enabled.borrow_mut();

        match &event.etype {
            EventType::TrayIconClicked => {
                // TODO: fetch top matches for the active config to be added

                // Non-actionable header line reflecting espanso's current status,
                // so the state is legible at a glance (native menu convention).
                let status_label = if *is_secure_input_enabled {
                    "espanso: secure input is blocking expansions"
                } else if *is_enabled {
                    "espanso: active"
                } else {
                    "espanso: disabled"
                };
                let status_header = MenuItem::Simple(SimpleMenuItem {
                    id: CONTEXT_ITEM_STATUS_HEADER,
                    label: status_label.to_string(),
                    checked: false,
                    enabled: false,
                });

                // Single toggle carrying a native checkmark instead of swapping
                // the label between "Enable"/"Disable". Clicking it flips state.
                let toggle_enabled = MenuItem::Simple(SimpleMenuItem {
                    id: if *is_enabled {
                        CONTEXT_ITEM_DISABLE
                    } else {
                        CONTEXT_ITEM_ENABLE
                    },
                    label: "Enabled".to_string(),
                    checked: *is_enabled,
                    enabled: true,
                });

                let mut items = vec![
                    status_header,
                    MenuItem::Separator,
                    toggle_enabled,
                    MenuItem::Simple(SimpleMenuItem::new(
                        CONTEXT_ITEM_OPEN_SEARCH,
                        "Open search bar",
                    )),
                    MenuItem::Separator,
                    MenuItem::Simple(SimpleMenuItem::new(CONTEXT_ITEM_RELOAD, "Reload config")),
                    MenuItem::Simple(SimpleMenuItem::new(
                        CONTEXT_ITEM_OPEN_CONFIG_FOLDER,
                        "Open config folder",
                    )),
                    MenuItem::Simple(SimpleMenuItem::new(CONTEXT_ITEM_SHOW_LOGS, "Show logs")),
                    MenuItem::Separator,
                    MenuItem::Simple(SimpleMenuItem::new(CONTEXT_ITEM_EXIT, "Exit espanso")),
                ];

                if *is_secure_input_enabled {
                    // Surface the secure-input remedies right below the header.
                    items.insert(
                        2,
                        MenuItem::Simple(SimpleMenuItem::new(
                            CONTEXT_ITEM_SECURE_INPUT_EXPLAIN,
                            "Why is espanso not working?",
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

                // TODO: my idea is to use a set of reserved u32 ids for built-in
                // actions such as Exit, Open Editor etc
                // then we need some u32 for the matches, so we need to create
                // a mapping structure match_id <-> context-menu-id
                Event::caused_by(
                    event.source_id,
                    EventType::ShowContextMenu(ShowContextMenuEvent {
                        // TODO: add actual entries
                        items,
                    }),
                )
            }
            EventType::ContextMenuClicked(context_click_event) => {
                match context_click_event.context_item_id {
                    CONTEXT_ITEM_EXIT => Event::caused_by(
                        event.source_id,
                        EventType::ExitRequested(ExitMode::ExitAllProcesses),
                    ),
                    CONTEXT_ITEM_RELOAD => Event::caused_by(
                        event.source_id,
                        EventType::ExitRequested(ExitMode::RestartWorker),
                    ),
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
                    CONTEXT_ITEM_SHOW_LOGS => {
                        dispatch(Event::caused_by(event.source_id, EventType::ShowLogs));
                        Event::caused_by(event.source_id, EventType::NOOP)
                    }
                    CONTEXT_ITEM_OPEN_CONFIG_FOLDER => {
                        dispatch(Event::caused_by(
                            event.source_id,
                            EventType::ShowConfigFolder,
                        ));
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
                *is_enabled = false;
                event
            }
            EventType::Enabled => {
                *is_enabled = true;
                event
            }
            EventType::SecureInputEnabled(_) => {
                *is_secure_input_enabled = true;
                event
            }
            EventType::SecureInputDisabled => {
                *is_secure_input_enabled = false;
                event
            }
            _ => event,
        }
    }
}
