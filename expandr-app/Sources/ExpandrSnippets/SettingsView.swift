import SwiftUI
import AppKit

/// Preferences (⌘,) — manage the folders Expandr reads snippets from. The first
/// (built-in) source is espanso's own match dir; additional sources are shared
/// or external folders and can be marked read-only.
struct SettingsView: View {
    @ObservedObject var store: SnippetStore
    @State private var removing: SnippetSource?

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
        .frame(width: 520, height: 360)
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
}
