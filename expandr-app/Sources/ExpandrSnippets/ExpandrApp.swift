import SwiftUI

@main
struct ExpandrSnippetsApp: App {
    var body: some Scene {
        WindowGroup("Expandr Snippets") {
            ContentView()
                .frame(minWidth: 820, minHeight: 480)
        }
        .windowToolbarStyle(.unified)
    }
}
