import SwiftUI

@main
struct ExpandrSnippetsApp: App {
    var body: some Scene {
        // A single Window (not WindowGroup) — one window, and no "New Window"
        // item / ⌘N in the File menu.
        Window("Expandr Snippets", id: "main") {
            ContentView()
                .frame(minWidth: 820, minHeight: 480)
        }
        .windowToolbarStyle(.unified)
    }
}
