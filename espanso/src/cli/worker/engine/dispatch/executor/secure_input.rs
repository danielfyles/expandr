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
use std::process::Stdio;

use anyhow::{bail, Context};
use log::{error, info};

use espanso_engine::dispatch::SecureInputManager;

pub struct SecureInputManagerAdapter {}

impl SecureInputManagerAdapter {
    pub fn new() -> Self {
        Self {}
    }
}

impl SecureInputManager for SecureInputManagerAdapter {
    /// Explain Secure Input in a native alert — self-contained, no website —
    /// naming the app that appears to hold it, and offer to run the auto-fix
    /// straight from the alert.
    #[cfg(target_os = "macos")]
    fn display_secure_input_troubleshoot(&self) -> anyhow::Result<()> {
        let app = espanso_mac_utils::get_secure_input_application()
            .map(|(name, _path)| name)
            .filter(|name| !name.trim().is_empty());

        let (culprit, hint) = match &app {
            Some(name) => (
                format!("an app — probably {name} — has a password field focused"),
                format!("Click into {name} and close, or move away from, its password field."),
            ),
            None => (
                "an app has a password field focused".to_string(),
                "Find the app with a password field and close, or move away from, it.".to_string(),
            ),
        };
        let message = format!(
            "macOS “Secure Input” is switched on: {culprit}. While it's on, macOS blocks \
             every app from typing, so your snippets can't expand.\n\n\
             To fix it: {hint} If that doesn't help, run the auto-fix, or lock and unlock \
             your screen."
        );
        let script = format!(
            "display alert \"Expandr can't expand right now\" message \"{}\" as warning \
             buttons {{\"Run auto-fix\", \"OK\"}} default button \"OK\"",
            applescript_escape(&message)
        );

        let chosen = run_osascript(&script)?;
        if chosen.contains("Run auto-fix") {
            self.launch_secure_input_autofix()?;
        }
        Ok(())
    }

    /// Secure Input is a macOS concept; there is nothing to explain elsewhere.
    #[cfg(not(target_os = "macos"))]
    fn display_secure_input_troubleshoot(&self) -> anyhow::Result<()> {
        Ok(())
    }

    fn launch_secure_input_autofix(&self) -> anyhow::Result<()> {
        let espanso_path = std::env::current_exe()?;
        let child = std::process::Command::new(espanso_path)
            .args(["workaround", "secure-input"])
            .stdout(Stdio::piped())
            .spawn()
            .context("unable to spawn workaround process")?;
        let output = child.wait_with_output()?;
        let output_str = String::from_utf8_lossy(&output.stdout);
        let error_str = String::from_utf8_lossy(&output.stderr);

        if output.status.success() {
            info!("Secure input workaround executed successfully: {output_str}");
            Ok(())
        } else {
            error!("Secure input autofix reported error: {error_str}");
            bail!("non-successful autofix status code");
        }
    }
}

/// Escape a string for use inside an AppleScript string literal. Order matters:
/// backslashes first, then quotes, then raw newlines become the two-character
/// `\n` escape (which AppleScript understands) without being re-escaped.
#[cfg(target_os = "macos")]
fn applescript_escape(text: &str) -> String {
    text.replace('\\', "\\\\")
        .replace('"', "\\\"")
        .replace('\n', "\\n")
}

/// Run an AppleScript via `osascript -` (script on stdin) and return its stdout.
/// A non-zero exit (e.g. the user dismissing the alert with Escape) is logged,
/// not treated as an error.
#[cfg(target_os = "macos")]
fn run_osascript(script: &str) -> anyhow::Result<String> {
    use std::io::Write;
    let mut child = std::process::Command::new("osascript")
        .arg("-")
        .stdin(Stdio::piped())
        .stdout(Stdio::piped())
        .stderr(Stdio::piped())
        .spawn()
        .context("unable to spawn osascript")?;
    child
        .stdin
        .take()
        .context("osascript stdin unavailable")?
        .write_all(script.as_bytes())?;
    let output = child.wait_with_output()?;
    if !output.status.success() {
        info!(
            "osascript exited non-zero: {}",
            String::from_utf8_lossy(&output.stderr).trim()
        );
    }
    Ok(String::from_utf8_lossy(&output.stdout).to_string())
}
