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

#[derive(Debug, Clone, PartialEq)]
pub struct ShowContextMenuEvent {
    pub items: Vec<MenuItem>,
}

#[derive(Debug, Clone, PartialEq)]
pub enum MenuItem {
    Simple(SimpleMenuItem),
    Sub(SubMenuItem),
    Separator,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct SimpleMenuItem {
    pub id: u32,
    pub label: String,
    // Whether the item displays a checkmark (rendered natively, e.g. via
    // `NSMenuItem.state` on macOS). Used for toggle-style items.
    pub checked: bool,
    // Whether the item is interactive. Disabled items render greyed-out and
    // non-clickable — used for the non-actionable status header line.
    pub enabled: bool,
}

impl SimpleMenuItem {
    // A regular, clickable menu item with no checkmark.
    pub fn new(id: u32, label: &str) -> Self {
        Self {
            id,
            label: label.to_string(),
            checked: false,
            enabled: true,
        }
    }
}

#[derive(Debug, Clone, PartialEq)]
pub struct SubMenuItem {
    pub label: String,
    pub items: Vec<MenuItem>,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct IconStatusChangeEvent {
    pub status: IconStatus,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum IconStatus {
    Enabled,
    Disabled,
    SecureInputDisabled,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ShowTextEvent {
    pub title: String,
    pub text: String,
}
