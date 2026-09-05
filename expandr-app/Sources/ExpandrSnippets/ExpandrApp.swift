import SwiftUI

@main
struct ExpandrSnippetsApp: App {
    // One store shared by the main window and the Settings (Preferences) window.
    @StateObject private var store = SnippetStore()
    @StateObject private var updater = Updater()

    var body: some Scene {
        // A single Window (not WindowGroup) — one window, and no "New Window"
        // item / ⌘N in the File menu.
        Window("Expandr Snippets", id: "main") {
            ContentView(store: store)
                .frame(minWidth: 820, minHeight: 480)
        }
        .windowToolbarStyle(.unified)
        .commands {
            CommandGroup(after: .appInfo) {
                Button("Check for Updates…") { updater.checkForUpdates() }
                    .disabled(!updater.canCheckForUpdates)
            }
        }

        // Preferences (⌘,) — manage additional snippet sources.
        Settings {
            SettingsView(store: store)
        }
    }
}
