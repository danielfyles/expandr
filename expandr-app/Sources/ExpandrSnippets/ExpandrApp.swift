import SwiftUI

@main
struct ExpandrSnippetsApp: App {
    // One store shared by the main window and the Settings (Preferences) window.
    @StateObject private var store = SnippetStore()

    var body: some Scene {
        // A single Window (not WindowGroup) — one window, and no "New Window"
        // item / ⌘N in the File menu.
        Window("Expandr Snippets", id: "main") {
            ContentView(store: store)
                .frame(minWidth: 820, minHeight: 480)
        }
        .windowToolbarStyle(.unified)

        // Preferences (⌘,) — manage additional snippet sources.
        Settings {
            SettingsView(store: store)
        }
    }
}
