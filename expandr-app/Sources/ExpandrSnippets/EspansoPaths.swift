import Foundation

/// Locates espanso's configuration directory, mirroring espanso's own
/// resolution order (see espanso/src/path/mod.rs::get_config_dir).
enum EspansoPaths {
    /// The active config directory, honouring the ESPANSO_CONFIG_DIR override
    /// (used by the side-by-side dev instance) then the standard locations.
    static func configDir() -> URL? {
        let fm = FileManager.default

        if let override = ProcessInfo.processInfo.environment["ESPANSO_CONFIG_DIR"] {
            return URL(fileURLWithPath: (override as NSString).expandingTildeInPath)
        }

        let home = fm.homeDirectoryForCurrentUser
        let candidates = [
            home.appendingPathComponent(".espanso"),
            home.appendingPathComponent(".config/espanso"),
            home.appendingPathComponent("Library/Preferences/espanso"),
            home.appendingPathComponent("Library/Application Support/espanso"),
        ]
        for dir in candidates where fm.fileExists(atPath: dir.path) {
            return dir
        }
        // Default even if it doesn't exist yet (espanso would create it).
        return home.appendingPathComponent("Library/Application Support/espanso")
    }

    /// The `match/` directory holding the snippet files.
    static func matchDir() -> URL? {
        configDir()?.appendingPathComponent("match")
    }
}
