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

//! `accessibility-status`: exit 0 if this process is trusted for Accessibility,
//! 1 otherwise (always 0 off macOS). Used by the launcher to poll for the grant
//! from a FRESH process — a process that was already running when the user
//! granted access keeps seeing a stale `AXIsProcessTrusted` answer, which is
//! why "restart the app" fixes it. A new process gets the current answer.

use super::{CliModule, CliModuleArgs};

pub fn new() -> CliModule {
    CliModule {
        subcommand: "accessibility-status".to_string(),
        entry: accessibility_status_main,
        ..Default::default()
    }
}

fn accessibility_status_main(_args: CliModuleArgs) -> i32 {
    #[cfg(target_os = "macos")]
    {
        if espanso_mac_utils::check_accessibility() { 0 } else { 1 }
    }
    #[cfg(not(target_os = "macos"))]
    {
        0
    }
}
