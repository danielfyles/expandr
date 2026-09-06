import Foundation

/// Manages the Expandr text-expansion engine (the `espanso` binary bundled inside
/// the shipping app and run as a launchd agent). In a dev build there is no
/// bundled engine, so every method safely no-ops.
enum EngineService {
    /// The engine binary, nested in its own sub-app inside the shipping bundle:
    /// Expandr.app/Contents/Helpers/Engine Agent.app/Contents/MacOS/espanso.
    static var bundledEngine: URL? {
        let url = Bundle.main.bundleURL
            .appendingPathComponent("Contents/Helpers/Engine Agent.app/Contents/MacOS/espanso")
        return FileManager.default.isExecutableFile(atPath: url.path) ? url : nil
    }

    /// Whether the launchd agent plist has been installed for this user.
    static var isRegistered: Bool {
        FileManager.default.fileExists(atPath: agentPlist.path)
    }

    private static var agentPlist: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents/app.expandr.plist")
    }

    /// Ensure the engine is registered and running. Called at launch: registers
    /// the launchd agent on first run (which triggers espanso's first-run wizard,
    /// including the macOS Accessibility prompt) and starts the service. Runs off
    /// the main thread; no-ops in a dev build (no bundled engine).
    static func ensureRunning() {
        guard bundledEngine != nil else { return }
        DispatchQueue.global(qos: .userInitiated).async {
            if !isRegistered { _ = run(["service", "register"]) }
            _ = run(["service", "start"])
        }
    }

    /// Restart the engine — used after an update swaps the app in place, so the
    /// launchd agent picks up the new binary.
    static func restart() {
        guard bundledEngine != nil else { return }
        DispatchQueue.global(qos: .userInitiated).async { _ = run(["service", "restart"]) }
    }

    /// Enable or disable "start at login" by registering / unregistering the
    /// launchd agent (register writes the RunAtLoad plist; unregister removes it).
    /// Enabling also starts the engine now so expansion works immediately.
    /// Returns the resulting registered state on the main queue via `completion`.
    static func setStartAtLogin(_ enabled: Bool, completion: @escaping (Bool) -> Void) {
        guard bundledEngine != nil else { completion(false); return }
        DispatchQueue.global(qos: .userInitiated).async {
            if enabled {
                if !isRegistered { _ = run(["service", "register"]) }
                _ = run(["service", "start"])
            } else {
                _ = run(["service", "unregister"])
            }
            let state = isRegistered
            DispatchQueue.main.async { completion(state) }
        }
    }

    /// Run the bundled engine with `args`, returning its exit status and output.
    @discardableResult
    private static func run(_ args: [String]) -> (status: Int32, output: String) {
        guard let engine = bundledEngine else { return (-1, "") }
        let process = Process()
        process.executableURL = engine
        process.arguments = args
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        do { try process.run() } catch { return (-1, "\(error)") }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return (process.terminationStatus, String(data: data, encoding: .utf8) ?? "")
    }
}
