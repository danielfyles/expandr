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

use crate::preferences::Preferences;
use crate::{
    exit_code::{
        LAUNCHER_ALREADY_RUNNING, LAUNCHER_CONFIG_DIR_POPULATION_FAILURE, LAUNCHER_SUCCESS,
    },
    lock::acquire_daemon_lock,
};
use log::{error, info};

use super::{CliModule, CliModuleArgs};

mod accessibility;
mod daemon;
#[cfg(feature = "modulo")]
mod edition_check;
mod util;

pub fn new() -> CliModule {
    #[allow(clippy::needless_update)]
    CliModule {
        requires_paths: true,
        enable_logs: false,
        subcommand: "launcher".to_string(),
        show_in_dock: true,
        entry: launcher_main,
        ..Default::default()
    }
}

#[cfg(feature = "modulo")]
fn launcher_main(args: CliModuleArgs) -> i32 {
    use espanso_modulo::wizard::{MigrationResult, WizardHandlers, WizardOptions};
    let paths = args.paths.expect("missing paths in launcher main");

    // If espanso is already running, show a warning
    let lock_file = acquire_daemon_lock(&paths.runtime);
    if lock_file.is_none() {
        util::show_already_running_warning().expect("unable to show already running warning");
        return LAUNCHER_ALREADY_RUNNING;
    }
    drop(lock_file);

    let paths_overrides = args
        .paths_overrides
        .expect("missing paths overrides in launcher main");
    let icon_paths =
        crate::icon::load_icon_paths(&paths.runtime).expect("unable to load icon paths");

    let preferences =
        crate::preferences::get_default(&paths.runtime).expect("unable to initialize preferences");

    let is_welcome_page_enabled = !preferences.has_completed_wizard();

    let is_move_bundle_page_enabled = crate::cli::util::is_subject_to_app_translocation_on_macos();

    let is_legacy_version_page_enabled = false;
    let is_legacy_version_running_handler = Box::new(util::is_legacy_version_running);

    let (is_wrong_edition_page_enabled, wrong_edition_detected_os) =
        edition_check::is_wrong_edition();

    let is_migrate_page_enabled = false;
    let backup_and_migrate_handler = Box::new(move || MigrationResult::Success);

    let is_auto_start_page_enabled =
        !preferences.has_selected_auto_start_option() && !cfg!(target_os = "linux");
    let preferences_clone = preferences.clone();
    let auto_start_handler = Box::new(move |auto_start| {
        preferences_clone.set_has_selected_auto_start_option(true);

        if auto_start {
            match util::configure_auto_start(true) {
                Ok(()) => true,
                Err(error) => {
                    eprintln!("Service register returned error: {error}");
                    false
                }
            }
        } else {
            true
        }
    });

    let is_add_path_page_enabled =
        if cfg!(not(target_os = "linux")) && !preferences.has_completed_wizard() {
            if cfg!(target_os = "macos") {
                !crate::path::is_espanso_in_path()
            } else if paths.is_portable_mode {
                false
            } else {
                !crate::path::is_espanso_in_path()
            }
        } else {
            false
        };
    let add_to_path_handler = Box::new(move || match util::add_espanso_to_path() {
        Ok(()) => true,
        Err(error) => {
            eprintln!("Add to path returned error: {error}");
            false
        }
    });

    let is_accessibility_page_enabled = if cfg!(target_os = "macos") {
        !accessibility::is_accessibility_enabled()
    } else {
        false
    };
    let is_accessibility_enabled_handler = Box::new(accessibility::is_accessibility_enabled);
    let enable_accessibility_handler = Box::new(move || {
        accessibility::prompt_enable_accessibility();
    });

    let on_completed_handler = Box::new(move || {
        preferences.set_completed_wizard(true);
    });

    // Only show the wizard if a panel should be displayed
    let should_launch_daemon = if is_welcome_page_enabled
        || is_move_bundle_page_enabled
        || is_auto_start_page_enabled
        || is_add_path_page_enabled
        || is_accessibility_page_enabled
        || is_wrong_edition_page_enabled
    {
        espanso_modulo::wizard::show(WizardOptions {
            version: crate::VERSION.to_string(),
            is_welcome_page_enabled,
            is_move_bundle_page_enabled,
            is_legacy_version_page_enabled,
            is_wrong_edition_page_enabled,
            is_migrate_page_enabled,
            is_auto_start_page_enabled,
            is_add_path_page_enabled,
            is_accessibility_page_enabled,
            window_icon_path: icon_paths
                .wizard_icon
                .map(|path| path.to_string_lossy().to_string()),
            welcome_image_path: icon_paths
                .logo_no_background
                .map(|path| path.to_string_lossy().to_string()),
            accessibility_image_1_path: icon_paths
                .accessibility_image_1
                .map(|path| path.to_string_lossy().to_string()),
            accessibility_image_2_path: icon_paths
                .accessibility_image_2
                .map(|path| path.to_string_lossy().to_string()),
            detected_os: wrong_edition_detected_os,
            handlers: WizardHandlers {
                is_legacy_version_running: Some(is_legacy_version_running_handler),
                backup_and_migrate: Some(backup_and_migrate_handler),
                auto_start: Some(auto_start_handler),
                add_to_path: Some(add_to_path_handler),
                enable_accessibility: Some(enable_accessibility_handler),
                is_accessibility_enabled: Some(is_accessibility_enabled_handler),
                on_completed: Some(on_completed_handler),
            },
        })
    } else {
        true
    };

    if let Err(err) = crate::config::populate_default_config(&paths.config) {
        error!("Error populating the config directory: {err:?}");

        // TODO: show an error message with GUI
        return LAUNCHER_CONFIG_DIR_POPULATION_FAILURE;
    }

    if should_launch_daemon {
        // We hide the dock icon on macOS to avoid having it around when the daemon is running
        #[cfg(target_os = "macos")]
        {
            espanso_mac_utils::convert_to_background_app();
        }

        daemon::launch_daemon(&paths_overrides).expect("failed to launch daemon");
    }

    LAUNCHER_SUCCESS
}

// Native launcher (no wxWidgets). There is no first-run wizard here — the
// SwiftUI app (Expandr Snippets) drives onboarding. This entry point just makes
// sure the config exists, requests macOS Accessibility permission, and starts
// the daemon. Registering the launchd service is handled by the app.
#[cfg(not(feature = "modulo"))]
fn launcher_main(args: CliModuleArgs) -> i32 {
    let paths = args.paths.expect("missing paths in launcher main");

    // Bail out if espanso is already running.
    let lock_file = acquire_daemon_lock(&paths.runtime);
    if lock_file.is_none() {
        error!("espanso is already running, refusing to launch a second instance");
        return LAUNCHER_ALREADY_RUNNING;
    }
    drop(lock_file);

    let paths_overrides = args
        .paths_overrides
        .expect("missing paths overrides in launcher main");

    // On macOS, Accessibility permission is required to detect and inject text,
    // and it must be granted BEFORE the worker starts: the keyboard event tap is
    // created at worker startup and one created without permission never
    // recovers (a first install would then not expand until a restart). So
    // prompt once, then wait here — the launcher is headless — until the user
    // grants it, and only then launch the daemon. The grant is live: no process
    // restart is needed for the check to flip.
    #[cfg(target_os = "macos")]
    {
        // Go headless FIRST: this launcher process is long-lived (launchd's parent
        // for the daemon), and if it is still a regular app while the Accessibility
        // prompt is up, macOS draws a Dock tile for it that never goes away.
        espanso_mac_utils::convert_to_background_app();
        if !accessibility::is_accessibility_enabled() {
            accessibility::prompt_enable_accessibility();
            // AXIsProcessTrusted stays STALE in a process that was already running
            // when the user granted access (only a fresh process gets the current
            // answer — that's why "restart the app" fixes it). So poll by spawning
            // this same binary as `accessibility-status` and reading its exit code.
            let started = std::time::Instant::now();
            let mut last_log = std::time::Instant::now();
            while !accessibility_granted_fresh() {
                std::thread::sleep(std::time::Duration::from_secs(1));
                if last_log.elapsed().as_secs() >= 30 {
                    info!(
                        "waiting for Accessibility permission to be granted ({}s so far)",
                        started.elapsed().as_secs()
                    );
                    last_log = std::time::Instant::now();
                }
            }
            info!(
                "Accessibility granted after {}s; starting the daemon",
                started.elapsed().as_secs()
            );
        }
    }

    if let Err(err) = crate::config::populate_default_config(&paths.config) {
        error!("Error populating the config directory: {err:?}");
        return LAUNCHER_CONFIG_DIR_POPULATION_FAILURE;
    }

    // Record that first-run setup is done so we don't keep prompting.
    if let Ok(preferences) = crate::preferences::get_default(&paths.runtime) {
        preferences.set_completed_wizard(true);
    }

    daemon::launch_daemon(&paths_overrides).expect("failed to launch daemon");

    LAUNCHER_SUCCESS
}

/// Accessibility check that survives a grant made while we were running: the
/// in-process check first (fast path), then a fresh child process's verdict via
/// the `accessibility-status` subcommand.
#[cfg(target_os = "macos")]
fn accessibility_granted_fresh() -> bool {
    if accessibility::is_accessibility_enabled() {
        return true;
    }
    let Ok(exe) = std::env::current_exe() else { return false };
    std::process::Command::new(exe)
        .arg("accessibility-status")
        .stdout(std::process::Stdio::null())
        .stderr(std::process::Stdio::null())
        .status()
        .map(|s| s.success())
        .unwrap_or(false)
}
