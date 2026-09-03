import SwiftUI

struct ContentView: View {
    @StateObject private var store = SnippetStore()
    @State private var selectedCategoryID: SnippetCategory.ID?
    @State private var selectedSnippetID: Snippet.ID?

    private var selectedCategory: SnippetCategory? {
        store.categories.first { $0.id == selectedCategoryID }
    }
    private var selectedSnippet: Snippet? {
        selectedCategory?.snippets.first { $0.id == selectedSnippetID }
    }

    var body: some View {
        NavigationSplitView {
            // ---- Left: categories (files) ----
            List(selection: $selectedCategoryID) {
                Section("Categories") {
                    ForEach(store.categories) { category in
                        Label(category.name, systemImage: "folder")
                            .badge(category.snippets.count)
                            .tag(category.id)
                    }
                }
            }
            .navigationSplitViewColumnWidth(min: 190, ideal: 220)
            .safeAreaInset(edge: .bottom) {
                // Placeholder for the ⚙︎ Preferences control (Phase 5).
                HStack {
                    Image(systemName: "gearshape").foregroundStyle(.secondary)
                    Text("Preferences").foregroundStyle(.secondary)
                    Spacer()
                }
                .padding(8)
            }
        } content: {
            // ---- Middle: snippets in the selected category ----
            if let category = selectedCategory {
                List(selection: $selectedSnippetID) {
                    ForEach(category.snippets) { snippet in
                        SnippetRow(snippet: snippet).tag(snippet.id)
                    }
                }
                .navigationTitle(category.name)
                .navigationSplitViewColumnWidth(min: 240, ideal: 300)
            } else {
                ContentUnavailableCompat("Select a category", systemImage: "folder")
            }
        } detail: {
            // ---- Right: snippet detail (read-only for now) ----
            if let snippet = selectedSnippet {
                SnippetDetail(snippet: snippet)
            } else {
                ContentUnavailableCompat("Select a snippet", systemImage: "text.cursor")
            }
        }
        .overlay(alignment: .bottom) {
            if let error = store.loadError {
                Text(error)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .padding(8)
            }
        }
    }
}

struct SnippetRow: View {
    let snippet: Snippet
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(snippet.primaryText).font(.body)
            if !snippet.previewText.isEmpty {
                Text(snippet.previewText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(.vertical, 2)
    }
}

struct SnippetDetail: View {
    let snippet: Snippet
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if let label = snippet.label, !label.isEmpty {
                    Text(label).font(.title2).bold()
                }
                field("Trigger", snippet.triggers.joined(separator: ", "))
                if let regex = snippet.regex { field("Regex", regex) }
                field("Type", snippet.kind.rawValue)
                if let replace = snippet.replace {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Replacement").font(.headline)
                        Text(replace)
                            .font(.body.monospaced())
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(10)
                            .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
                    }
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .navigationTitle(snippet.primaryText)
    }

    @ViewBuilder private func field(_ title: String, _ value: String) -> some View {
        if !value.isEmpty {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                Text(value).textSelection(.enabled)
            }
        }
    }
}

/// Minimal fallback for ContentUnavailableView (macOS 14+) so we run on macOS 13.
struct ContentUnavailableCompat: View {
    let title: String
    let systemImage: String
    init(_ title: String, systemImage: String) {
        self.title = title
        self.systemImage = systemImage
    }
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: systemImage).font(.largeTitle).foregroundStyle(.tertiary)
            Text(title).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
