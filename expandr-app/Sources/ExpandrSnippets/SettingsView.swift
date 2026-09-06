import SwiftUI
import AppKit

/// Preferences (⌘,) — a tabbed window. **General** covers system permissions and
/// launch behaviour; **Sources** manages the folders Expandr reads snippets from.
struct SettingsView: View {
    @ObservedObject var store: SnippetStore

    var body: some View {
        TabView {
            GeneralSettingsView()
                .tabItem { Label("General", systemImage: "gearshape") }
            SourcesSettingsView(store: store)
                .tabItem { Label("Sources", systemImage: "folder") }
        }
        .frame(width: 560)
    }
}

// MARK: - General

/// System permissions and launch behaviour. Accessibility is what actually lets
/// the engine type expansions, so give the user a one-click path to confirm it;
/// "Start at login" re-arms the background agent if its permission was rescinded.
struct GeneralSettingsView: View {
    // Mirrors whether the launchd agent is registered (RunAtLoad). Seeded on
    // appear and after each toggle so the UI reflects the real state.
    @State private var startAtLogin = EngineService.isRegistered
    // Guards against the onChange firing when we set the value programmatically.
    @State private var syncingToggle = false

    var body: some View {
        Form {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Accessibility permission")
                        .font(.body.weight(.semibold))
                    Text("Expandr needs macOS Accessibility permission to type your expansions. If expansions stop working, open Accessibility settings and make sure Expandr (and its Engine Agent) is enabled.")
                        .font(.callout).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Button("Open Accessibility Settings…") {
                        openAccessibilitySettings()
                    }
                }
                .padding(.vertical, 4)
            }

            Section {
                Toggle("Start Expandr at login", isOn: $startAtLogin)
                    .onChange(of: startAtLogin) { newValue in
                        guard !syncingToggle else { return }
                        EngineService.setStartAtLogin(newValue) { actual in
                            syncingToggle = true
                            startAtLogin = actual
                            syncingToggle = false
                        }
                    }
                Text("Keeps the background engine running so your snippets expand in every app. Turn this off to stop Expandr launching automatically.")
                    .font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .formStyle(.grouped)
        .frame(height: 300)
        .onAppear {
            syncingToggle = true
            startAtLogin = EngineService.isRegistered
            syncingToggle = false
        }
    }

    /// Deep-link straight to System Settings ▸ Privacy & Security ▸ Accessibility.
    private func openAccessibilitySettings() {
        if let url = URL(string:
            "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }
}

// MARK: - Sources

/// Manage the folders Expandr reads snippets from. The first (built-in) source is
/// espanso's own match dir; additional sources are shared or external folders and
/// can be marked read-only.
struct SourcesSettingsView: View {
    @ObservedObject var store: SnippetStore
    @State private var removing: SnippetSource?
    // The source whose "online-only" explanation modal is currently open.
    @State private var explaining: SnippetSource?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header

            List {
                ForEach(store.sources) { source in
                    sourceRow(source)
                }
            }
            .listStyle(.inset(alternatesRowBackgrounds: true))

            Divider()
            HStack {
                Button {
                    addSource()
                } label: {
                    Label("Add Source…", systemImage: "plus")
                }
                Spacer()
            }
            .padding(12)
        }
        .frame(height: 360)
        .confirmationDialog(
            "Remove this source?",
            isPresented: Binding(get: { removing != nil }, set: { if !$0 { removing = nil } }),
            titleVisibility: .visible
        ) {
            Button("Remove", role: .destructive) {
                if let source = removing { store.removeSource(source.id) }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Expandr will stop reading from this folder. The folder and its files are left untouched.")
        }
        .sheet(item: $explaining) { source in
            OfflineWarningView(source: source) { explaining = nil }
        }
        .onAppear { store.revalidateAvailability() }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Sources").font(.title2.weight(.semibold))
            Text("Folders of snippet files that Expandr reads and expands (saved in YAML format).")
                .font(.callout).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
        .padding(.top, 16)
        .padding(.bottom, 10)
    }

    @ViewBuilder private func sourceRow(_ source: SnippetSource) -> some View {
        HStack(spacing: 12) {
            Image(systemName: source.isBuiltIn ? "house.fill" : "folder.fill")
                .foregroundStyle(source.isBuiltIn ? Color.accentColor : .secondary)
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 2) {
                Text(source.displayName).font(.body.weight(.medium))
                Text(source.isBuiltIn ? "Your main snippets folder" : source.path)
                    .font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
            }
            Spacer()
            if source.isBuiltIn {
                Text("Built-in").font(.caption).foregroundStyle(.tertiary)
            } else {
                // Cloud folder with online-only files → warn (click for details).
                if sourceMayBeUnavailable(source) {
                    Button { explaining = source } label: {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.red)
                    }
                    .buttonStyle(.borderless)
                    .help("This folder may not always be available — click to learn more")
                }
                // A padlock: click to lock (read-only) or unlock (editable). The
                // "Read-only" wording only appears once it's locked — a closed
                // padlock reads as read-only on its own.
                Button {
                    store.setSourceReadOnly(source.id, !source.isReadOnly)
                } label: {
                    HStack(spacing: 5) {
                        if source.isReadOnly {
                            Text("Read-only").font(.caption).foregroundStyle(.secondary)
                        }
                        Image(systemName: source.isReadOnly ? "lock.fill" : "lock.open")
                            .foregroundStyle(source.isReadOnly ? Color.accentColor : .secondary)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.borderless)
                .help(source.isReadOnly ? "Locked — click to allow editing" : "Click to lock (read-only)")
                Button(role: .destructive) {
                    removing = source
                } label: {
                    Image(systemName: "minus.circle")
                }
                .buttonStyle(.borderless)
                .help("Remove source")
            }
        }
        .padding(.vertical, 4)
    }

    /// Choose a folder; hand it to the store, which either adopts existing YAML
    /// files or seeds one default file named after the folder.
    private func addSource() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Add Source"
        panel.message = "Choose a folder containing (or to contain) snippet files in YAML format."
        if panel.runModal() == .OK, let url = panel.url {
            store.addSource(url)
        }
    }

    /// True if any of the source's files is online-only (not downloaded). The
    /// store flags these during load (via a metadata-only stat, without
    /// materializing them), so this just reads that flag.
    private func sourceMayBeUnavailable(_ source: SnippetSource) -> Bool {
        store.categories.contains { $0.sourceID == source.id && $0.isOnlineOnly }
    }
}

/// Explains the cloud-folder "online-only" problem and how to fix it. The fix
/// screenshot is bundled as `offline-fix.png` when present.
struct OfflineWarningView: View {
    let source: SnippetSource
    let onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 10) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.title).foregroundStyle(.red)
                Text("This folder might not always be available")
                    .font(.title3.weight(.semibold))
            }
            Text("“\(source.displayName)” is stored in a cloud folder (Google Drive or similar). Some of its snippet files are kept online-only and downloaded on demand.\n\nWhile a file is online-only, its snippets won't expand when you're offline or before it has synced — and updates to it may not be picked up reliably.")
                .fixedSize(horizontal: false, vertical: true)
            Text("To fix it, make the folder always available offline:")
                .font(.callout.weight(.semibold))
            fixImage
            Text("In Finder, right-click the folder and choose “Make available offline”.")
                .font(.callout).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Spacer()
                Button("Done", action: onClose).keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 460)
        // Demand the natural height so the sheet sizes to content and isn't
        // squished by the Settings window's fixed height.
        .fixedSize(horizontal: false, vertical: true)
    }

    @ViewBuilder private var fixImage: some View {
        if let url = Bundle.main.url(forResource: "offline-fix", withExtension: "png"),
           let image = NSImage(contentsOf: url) {
            Image(nsImage: image)
                .resizable().scaledToFit()
                .frame(maxWidth: .infinity)
                .frame(height: 230)   // definite height so it can't be compressed
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(.quaternary))
        } else {
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.secondary.opacity(0.08))
                .frame(height: 130)
                .overlay(
                    Label("Screenshot", systemImage: "photo")
                        .font(.caption).foregroundStyle(.tertiary))
                .overlay(RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(Color.secondary.opacity(0.3),
                                  style: StrokeStyle(lineWidth: 1, dash: [4, 3])))
        }
    }
}
