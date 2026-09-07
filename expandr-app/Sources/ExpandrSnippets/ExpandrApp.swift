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
        .defaultSize(width: 980, height: 640)
        .defaultPosition(.center)
        .commands {
            CommandGroup(replacing: .appInfo) {
                Button("About Expandr") { showAboutPanel() }
            }
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

/// Show a standard About panel that also links to the expandr.app holding page.
/// Name, icon and version come from Info.plist automatically; we add the credits.
private func showAboutPanel() {
    let credits = NSMutableAttributedString(
        string: NSLocalizedString("A native macOS text expander.", comment: "About panel tagline") + "\n\n",
        attributes: [
            .font: NSFont.systemFont(ofSize: 11),
            .foregroundColor: NSColor.secondaryLabelColor,
        ])
    let link = NSMutableAttributedString(
        string: "expandr.app",
        attributes: [
            .font: NSFont.systemFont(ofSize: 11),
            .link: URL(string: "https://expandr.app")!,
        ])
    credits.append(link)

    let paragraph = NSMutableParagraphStyle()
    paragraph.alignment = .center
    credits.addAttribute(.paragraphStyle, value: paragraph,
                         range: NSRange(location: 0, length: credits.length))

    NSApp.activate(ignoringOtherApps: true)
    NSApp.orderFrontStandardAboutPanel(options: [.credits: credits])
}
